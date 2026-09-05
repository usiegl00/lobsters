# typed: false

# Finds the consistent most-heavily-flagged commenters. Requires flags to be spread over
# several comments and stories because anyone can have a bad thread or a bad day.

class FlaggedCommenters
  include IntervalHelper

  attr_reader :interval, :period, :cache_time

  def initialize(interval, cache_time = 30.minutes)
    @interval = interval
    @cache_time = cache_time
    length = time_interval(interval)
    @period = length[:dur].send(length[:intv].downcase).ago
  end

  def check_list_for(showing_user)
    commenters[showing_user.id]
  end

  # aggregates for all commenters; not just those receiving flags
  def aggregates
    Rails.cache.fetch("aggregates_#{interval}_#{cache_time}", expires_in: cache_time) {
      ActiveRecord::Base.connection.exec_query("
        select
          stddev(sum_flags) as stddev,
          sum(sum_flags) as sum,
          avg(sum_flags) as avg,
          avg(n_comments) as n_comments,
          count(*) as n_commenters
        from (
          select
            sum(flags) as sum_flags,
            count(*) as n_comments
          from comments join users on comments.user_id = users.id
          where
            (comments.created_at >= '#{period}') and
            users.banned_at is null and
            users.deleted_at is null
          GROUP BY comments.user_id
        ) sums;
      ").first.symbolize_keys!
    }
  end

  def stddev_sum_flags
    aggregates[:stddev].to_f
  end

  def avg_sum_flags
    aggregates[:avg].to_f
  end

  def commenters
    Rails.cache.fetch(
      "flagged_commenters_#{interval}_#{cache_time}",
      expires_in: cache_time
    ) do
      rank = 0

      users = User.arel_table
      comments = Comment.arel_table

      quoted = ->(value) { Arel::Nodes.build_quoted(value) }

      flagged_comment_id = Arel::Nodes::Case.new
        .when(comments[:flags].gt(0))
        .then(comments[:id])

      flagged_story_id = Arel::Nodes::Case.new
        .when(comments[:flags].gt(0))
        .then(comments[:story_id])

      n_comments = Arel::Nodes::Count.new(
        [flagged_comment_id],
        true
      )

      n_stories = Arel::Nodes::Count.new(
        [flagged_story_id],
        true
      )

      n_flags = comments[:flags].sum

      total_comments = Arel::Nodes::Count.new(
        [comments[:id]],
        true
      )

      # Multiplying by 1.0 forces non-integer division on databases
      # where integer / integer would truncate.
      average_flags =
        (n_flags * quoted.call(1.0)) / total_comments

      percent_flagged =
        ((n_comments * quoted.call(1.0)) / total_comments) *
          quoted.call(100.0)

      sigma =
        ((n_flags - quoted.call(avg_sum_flags)) * quoted.call(1.0)) /
          quoted.call(stddev_sum_flags)

      having =
        n_comments.gt(4)
          .and(n_stories.gt(1))
          .and(n_flags.gteq(10))
          .and(percent_flagged.gt(10))

      User.active
        .joins(:comments)
        .where(comments[:created_at].gteq(period))
        .group(users[:id], users[:username])
        .select(
          users[:id],
          users[:username],
          sigma.as("sigma"),
          n_comments.as("n_comments"),
          n_stories.as("n_stories"),
          n_flags.as("n_flags"),
          average_flags.as("average_flags"),
          percent_flagged.as("percent_flagged")
        )
        .having(having)
        .order(sigma.desc)
        .limit(30)
        .each_with_object({}) do |u, hash|
          hash[u.id] = {
            username: u.username,
            rank: rank += 1,
            sigma: u.sigma,
            n_comments: u.n_comments,
            n_stories: u.n_stories,
            n_flags: u.n_flags,
            average_flags: u.average_flags,
            stddev: 0,
            percent_flagged: u.percent_flagged
          }
        end
    end
  end
end
