class ResticJob < ApplicationJob
  queue_as :default

  def restic_env(path)
    File.readlines(path).each_with_object({}) do |line, env|
      line = line.strip
      next if line.blank? || line.start_with?("#")

      key, value = line.delete_prefix("export ").split("=", 2)
      next unless key&.match?(/\A[A-Z0-9_]+\z/) && value

      env[key] = value.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
    end
  end

  def perform(*args)
    return unless ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")

    home = "/home/deploy"
    shared = "#{home}/lobsters/shared"
    unless File.directory?(shared)
      raise "ResticJob: shared path '#{shared}' does not exist, can't back up"
    end
    db_path = Rails.root.join("storage/primary.sqlite3")
    system(Rails.root.join("bin/sqlite3").to_s, db_path.to_s,
      ".backup '#{shared}/database-backups/primary.sqlite3'", exception: true)
    restic_env_path = "#{shared}/etc/restic-env"
    unless File.file?(restic_env_path)
      raise "ResticJob: env path '#{restic_env_path}' does not exist, can't back up"
    end

    system(restic_env(restic_env_path),
      "restic", "backup", "--no-scan",
      "#{shared}/etc", "#{shared}/log", "#{shared}/database-backups", "#{home}/.*_history",
      exception: true)
  end
end
