# typed: false

# Comment.above_average needs to compare against the average, which is an expensive dependent
# subquery. CommentStat calculates and stores that once for a fast join.
class CommentStat < ApplicationRecord
  # has_many :comments # date(comments.created_at)

  validates :date, presence: true, uniqueness: true
  validates :average, presence: true

  # Fills daily records for the last 30 days, updating existing rows (in case the job runs don't
  # line up to date boundaries).
  def self.daily_fill!
    date_sql = if Comment.connection.adapter_name.downcase.start_with?("postgresql")
      "(created_at - interval '5 hours')::date"
    else
      "date(created_at, '-5 hours')"
    end

    averages = Comment
      .where(is_deleted: false)
      .where("created_at >= ?", 30.days.ago + 5.hours)
      .group(Arel.sql(date_sql))
      .average(:score)

    rows = averages.map { |date, average|
      {
        date: date,
        average: average.to_i
      }
    }
    return if rows.empty?

    upsert_all(rows, unique_by: :idx_comment_stats_on_date)
  end
end
