# frozen_string_literal: true
module Split
  class ExperimentCatalog
    # Return all experiments
    def self.all
      # Call compact to prevent nil experiments from being returned -- seems to happen during gem upgrades
      Split.redis.smembers(:experiments).map {|e| find(e)}.compact
    end

    # Return experiments without a winner (considered "active") first
    def self.all_active_first
      all.partition{|e| not e.winner}.map{|es| es.sort_by(&:name)}.flatten
    end

    def self.find(name)
      return unless Split.redis.exists(name)
      Experiment.new(name).tap { |exp| exp.load_from_redis }
    end

    def self.find_or_initialize(metric_descriptor, control = nil, *alternatives)
      catalog = self.new()
      catalog.find_or_initialize(metric_descriptor, control, *alternatives)
    end

    def self.find_or_create(metric_descriptor, control = nil, *alternatives)
      experiment = find_or_initialize(metric_descriptor, control, *alternatives)
      experiment.save
    end

    def self.normalize_experiment(metric_descriptor)
      if Hash === metric_descriptor
        experiment_name = metric_descriptor.keys.first
        goals = Array(metric_descriptor.values.first)
      else
        experiment_name = metric_descriptor
        goals = []
      end
      return experiment_name, goals
    end

    def initialize
    end

    def find(name)
      return unless experiment_exists(name)
      Experiment.new(name, catalog: self).tap { |exp| exp.load_from_redis }
    end

    def find_or_initialize(metric_descriptor, control = nil, *alternatives)
      # Check if array is passed to ab_test
      # e.g. ab_test('name', ['Alt 1', 'Alt 2', 'Alt 3'])
      if control.is_a? Array and alternatives.length.zero?
        control, alternatives = control.first, control[1..-1]
      end

      experiment_name_with_version, goals = ExperimentCatalog.normalize_experiment(metric_descriptor)
      experiment_name = experiment_name_with_version.to_s.split(':')[0]
      Split::Experiment.new(experiment_name,
          :alternatives => [control].compact + alternatives, :goals => goals, catalog: self)
    end

    def winner(test)
      @winners = Split.redis.hgetall(:experiment_winner) unless @winners
      @winners[test]
    end


    def clear_winners
      @winners = nil
    end

    def start_time(test)
      @start_times = Split.redis.hgetall(:experiment_start_times) unless @start_times
      @start_times[test]
    end

    def clear_start_times
      @start_times = nil
    end

    def experiment_exists(name)
      @experiments ||= {}
      unless @experiments.has_key?(name)
        @experiments[name] = Split.redis.exists(name)
      end
      @experiments[name]
    end

    def add_experiment_exists(name)
      @experiments ||= {}
      @experiments[name] = true
    end

    def clear_experiment_exists(name)
      @experiments.delete(name) if @experiments
    end

    def experiment_config(name)
      @experiments_config ||= {}
      unless @experiments_config.has_key?(name)
        @experiments_config[name] = Split.redis.hgetall(name)
      end
      @experiments_config[name]
    end

    def clear_experiment_config(name)
      @experiments_config.delete(name) if @experiments_config
    end
  end
end
