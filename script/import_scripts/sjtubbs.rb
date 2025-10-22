# frozen_string_literal: true

require_relative "base"
require "pg"

class ImportScripts::SJTUBBS < ImportScripts::Base
  BATCH_SIZE = 5000

  def initialize
    super
    @connection =
      PG.connect(host: "172.17.0.1", port: 5432, user: "root", password: "example", dbname: "root")
  end

  def import_users
    puts "Importing users..."
    total_count = @connection.exec("SELECT COUNT(*) FROM authors;").first["count"]
    batches(BATCH_SIZE) do |offset|
      users =
        @connection.exec("SELECT id, username FROM authors LIMIT #{BATCH_SIZE} OFFSET #{offset};")
      break if users.to_a.size < 1
      create_users(users, total: total_count, offset: offset) do |user|
        {
          id: "user#" + user["id"],
          username: user["username"][/[a-z0-9A-Z_-]+/i].strip,
          email: "#{user["username"][/[a-z0-9A-Z_-]+/i].strip}@example.com",
          created_at: Time.now,
        }
      end
    end
  end

  def import_categories
    boards = @connection.exec("SELECT id, name FROM boards;")
    create_categories(boards) do |board|
      {
        id: "category#" + board["id"],
        name: board["name"],
        description: "sjtubbs #{board["name"]}",
      }
    end
  end

  def import_topics
    puts "", "importing topics..."
    topic_count = @connection.exec("SELECT COUNT(*) FROM topics;").first["count"]
    batches(BATCH_SIZE) do |offset|
      topics =
        @connection.exec(
          "SELECT id, title, content, created_at, board_id, author_id FROM topics  ORDER BY id LIMIT #{BATCH_SIZE} OFFSET #{offset};",
        )
      break if topics.to_a.size < 1
      create_posts(topics, total: topic_count, offset: offset) do |topic|
        {
          id: "topic#" + topic["id"],
          user_id:
            user_id_from_imported_user_id("user#" + topic["author_id"]) ||
              Discourse::SYSTEM_USER_ID,
          title: topic["title"],
          raw: topic["content"],
          created_at: topic["created_at"],
          category_id: category_id_from_imported_category_id("category#" + topic["board_id"]),
        }
      end
    end
  end

  def import_posts
    post_count = @connection.exec("SELECT COUNT(*) FROM posts;").first["count"]
    batches(BATCH_SIZE) do |offset|
      posts =
        @connection.exec(
          "SELECT id, content, created_at, topic_id, author_id FROM posts  ORDER BY id LIMIT #{BATCH_SIZE} OFFSET #{offset};",
        )
      break if posts.to_a.size < 1
      create_posts(posts, total: post_count, offset: offset) do |post|
        {
          id: "post#" + post["id"],
          user_id:
            user_id_from_imported_user_id("user#" + post["author_id"]) || Discourse::SYSTEM_USER_ID,
          raw: post["content"],
          created_at: post["created_at"],
          topic_id: topic_lookup_from_imported_post_id("topic#" + post["topic_id"])[:topic_id],
        }
      end
    end
  end

  def execute
    import_users
    import_categories
    import_topics
    import_posts
  end
end

ImportScripts::SJTUBBS.new.perform
