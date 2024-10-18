module PtToGithub
  class Story
    def initialize(row:, archive_path:)
      @row = row
      @archive_path = archive_path
    end

    def method_missing(method_name, *args, &block)
      if method_name.to_s.end_with?('=')
        attribute_name = method_name.to_s.chop.to_sym
        @row[attribute_name] = args.first
      elsif @row.key?(method_name)
        @row[method_name]
      else
        super
      end
    end

    def description
      begin
        description = "
  This issue was imported from Pivotal Tracker.

  | Field | Value |
  | --- | --- |
  | Story ID | [##{id}](#{url}) |
  | State | #{current_state} |
  | Requested By | #{requested_by} |
  | Owned By | #{owned_by.join(", ")} |
  | Estimate | #{estimate} |
  | Priority | #{priority} |
  | Created At | #{created_at} |
  | Accepted At | #{accepted_at} |
      "

        description += "\n## Description\n#{@row[:description]}" if @row[:description]

        if blockers.any?
          description += "\n\n## Blockers\n"
          description += blockers.map { |b| "- #{b[:blocker]} (#{b[:status]})" }.join("\n")
        end

        if comments.any?
          description += "\n\n## Comments\n"
          description += comments.join("\n\n")
        end

        if pull_requests.any?
          description += "\n\n## Referenced Pull Requests\n"
          description += pull_requests.map { |p| "- #{p}" }.join("\n")
        end

        description
      end
    end

    def labels
      @labels ||= begin
        labels = @row[:labels].split(",").map(&:strip)

        labels << type
      end
    end

    def assets
      @assets ||= begin
        p = Pathname.new("#{@archive_path}/#{id}")
        p.exist? ? p.children : []
      end
    end
  end
end
