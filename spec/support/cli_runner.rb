# frozen_string_literal: true

require 'open3'

# Запуск CLI как внешнего процесса — проверяем коды выхода и текст без стектрейсов.
module CliHelper
  CliResult = Struct.new(:stdout, :stderr, :status) do
    def exit_code = status.exitstatus
    def output = stdout + stderr
  end

  def run_cli(*, env: {})
    stdout, stderr, status = Open3.capture3(env, 'bin/forge', *)
    CliResult.new(stdout, stderr, status)
  end

  def run_integrate(*)
    stdout, stderr, status = Open3.capture3('bin/integrate', *)
    CliResult.new(stdout, stderr, status)
  end
end

RSpec.configure { |c| c.include CliHelper }
