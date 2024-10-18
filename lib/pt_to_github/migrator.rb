require "pathname"
require "csv"

module PtToGithub
  class Migrator
    attr_reader :path, :client, :repo

    def initialize(path:, client:, repo:, user_map: {})
      @path = path
      @client = client
      @repo = repo
      @user_map = user_map
      @handled_ids = load_handled_ids
    end

    def run
      CSV.foreach(path, headers: true) do |row|

        story = build_story(row)

        if @handled_ids.include?(story.id)
          puts "skipping #{story.id} as it's already been handled"
          next
        end

        attempts = 0
        begin
          handle_story(story)
          attempts = 0
          sleep 1
        rescue => e
          attempts += 1
          if e.class == Octokit::TooManyRequests
            time_delay = [(2 ** attempts), 600].min
            puts "Too many requests - will try again in #{time_delay} seconds"
            sleep time_delay
            retry if attempts <= 20
          elsif e.class == Octokit::UnprocessableEntity && e.detailed_message.match?("422 - Validation Failed")
            value = JSON.parse(e.response_body)["errors"][0]["value"]
            puts "The mapped user (#{value}) doesn't have access to the repository. Removing that person."
            story.owned_by -= [@user_map.key(value)]
            retry if attempts <= 10
          end
          raise e
        end

        @handled_ids << story.id
      end
    ensure
      File.write(handled_ids_file, @handled_ids.to_a.join("\n"))
    end

    def handle_story(story)
      case story.type
      when "feature"
        create_issue(story)
      when "bug"
        create_issue(story)
      when "chore"
        create_issue(story)
      when "release"
        puts "skipping #{story.type} #{story.id}"
      when "epic"
        puts "skipping #{story.type} #{story.id}"
      end
    end

    def create_issue(story)
      puts "creating issue for #{story.id}"

      issue = client.create_issue(
        @repo,
        story.title,
        story.description,
        labels: story.labels,
        assignees: story.owned_by.map { |u| @user_map[u] }.compact
      )

      if story.current_state == "accepted"
        client.close_issue(@repo, issue.number)
      end
    end

    def build_story(row)
      obj = {
        comments: [],
        tasks: [],
        blockers: [],
        owned_by: [],
        pull_requests: []
      }

      queue = Queue.new
      row.each_with_index do |(header, value), index|
        header = header.downcase.gsub(" ", "_").to_sym
        queue << [header, value&.strip]
      end

      while queue.length > 0
        header, value = queue.shift

        case header
        when :comment
          next if value.nil?
          obj[:comments] << value
        when :task
          next if value.nil?
          status = queue.shift.last
          obj[:tasks] << { task: value, status: status }
        when :blocker
          next if value.nil?
          status = queue.shift.last
          obj[:blockers] << { blocker: value, status: status }
        when :owned_by
          next if value.nil?
          obj[:owned_by] << value
        when :pull_request
          next if value.nil?
          obj[:pull_requests] << value
        else
          obj[header] = value
        end
      end

      PtToGithub::Story.new(row: obj, archive_path: path.dirname)
    end

    protected

    def load_handled_ids
      if !File.exist?(handled_ids_file)
        FileUtils.mkdir_p(handled_ids_file.dirname)
        File.write(handled_ids_file, "")
      end

      @handled_ids = Set.new(File.read(handled_ids_file).split("\n"))
    end

    def handled_ids_file
      Pathname.new("out/#{path.basename}-handled-ids")
    end
  end
end
