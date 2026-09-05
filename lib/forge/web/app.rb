# frozen_string_literal: true

require 'sinatra/base'
require 'erb'
require 'json'
require 'open3'
require 'securerandom'
require 'fileutils'
require 'rubygems/package'
require 'stringio'
require_relative '../../forge'
require_relative '../generate_command'
require_relative 'runs'

module Forge
  module Web
    # Тонкий веб-слой поверх CLI: загрузить спеку → analyze / generate → посмотреть файлы, прогнать spec и e2e.
    # Никакой логики анализа здесь нет — всё через те же классы, что и bin/forge.
    class App < Sinatra::Base
      set :views, File.join(__dir__, 'views')
      set :public_folder, File.expand_path('../../../public', __dir__)
      set :bind, '0.0.0.0'
      set :port, ENV.fetch('PORT', 8080).to_i
      set :show_exceptions, false
      set :logging, true

      configure { Runs.root = ENV.fetch('FORGE_WORKDIR', File.expand_path('../../../tmp/web', __dir__)) }

      helpers do
        def h(text) = Rack::Utils.escape_html(text.to_s)
        def run = @run ||= Runs.find(params[:id]) || halt(404, erb(:not_found))
        def examples = Dir[File.expand_path('../../../examples/specs/*', __dir__)]
        def overrides_examples = Dir[File.expand_path('../../../examples/overrides/*.yml', __dir__)]
      end

      get '/' do
        @runs = Runs.recent(10)
        erb :index
      end

      post '/runs' do
        run = Runs.create(params)
        redirect "/runs/#{run.id}"
      rescue Forge::Error, ArgumentError => e
        @error = e.message
        @runs = Runs.recent(10)
        erb :index
      end

      get('/runs/:id') { erb :run }
      get '/runs/:id/report.json' do
        content_type :json
        run.report_json
      end

      get '/runs/:id/files/:name' do
        file = run.file(params[:name]) || halt(404, erb(:not_found))
        content_type file.end_with?('.md') ? 'text/markdown' : 'text/plain'
        send_file file, disposition: params[:download] ? 'attachment' : 'inline'
      end

      get '/runs/:id/download.tar' do
        content_type 'application/x-tar'
        attachment "#{run.provider}.tar"
        run.tar
      end

      %w[spec e2e].each do |step|
        post "/runs/:id/#{step}" do
          run.exec_step(step.to_sym)
          redirect "/runs/#{run.id}##{step}"
        end
      end

      post '/runs/:id/delete' do
        Runs.delete(run.id)
        redirect '/'
      end

      error Forge::Error do
        @error = env['sinatra.error'].message
        status 422
        erb :index
      end

      not_found { erb :not_found }
    end
  end
end
