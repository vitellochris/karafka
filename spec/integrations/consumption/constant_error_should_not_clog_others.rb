# frozen_string_literal: true

# Karafka should process other partitions data using same worker in which a job failed
# Workers should not hang when a job within them fails but should be available for other jobs
# Workers should not be clogged by a failing job

setup_karafka do |config|
  config.concurrency = 1
end

# Send data to all 3 partitions
# We need to remember last offset per partition as we need to seek back to always have
# 300 messages to consume tops from all 3 partitions
# There can be more if we run this in development several times
300.times do |i|
  result = produce('integrations_0_03', SecureRandom.uuid, partition: i % 3)
  DataCollector.data[:last_offsets][result.partition] = result.offset
end

class Consumer < Karafka::BaseConsumer
  def consume
    unless @seeked
      seek(DataCollector.data[:last_offsets][messages.metadata.partition] - 99)
      @seeked = true
      return
    end

    # We force this single partition to never process anything simulating a constant failure
    raise StandardError if messages.metadata.partition.zero?

    messages.each do |message|
      DataCollector.data[message.metadata.partition] << message.metadata.partition
    end
  end
end

draw_routes do
  consumer_group DataCollector.consumer_group do
    # Special topic with 3 partitions available
    topic 'integrations_0_03' do
      consumer Consumer
    end
  end
end

start_karafka_and_wait_until do
  # We subtract 3 as 3 values are from the offsets
  (DataCollector.data.values.map(&:size).sum - 3) >= 200
end

# No data for failing partition
assert_equal 0, DataCollector.data[0].size
assert_equal 100, DataCollector.data[1].size
assert_equal 100, DataCollector.data[2].size
# Extra checks for in-partition data consistency
assert_equal [1], DataCollector.data[1].uniq
assert_equal [2], DataCollector.data[2].uniq