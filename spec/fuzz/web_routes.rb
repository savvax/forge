# frozen_string_literal: true

module Fuzz
  # Часть rake fuzz:web про маршруты: чужие URL, обход путей, HTTP-методы, огромная загрузка, гонки с диском.
  module WebRoutes
    URLS = ['/runs/../../etc', '/runs/%2e%2e', '/runs/nope', '/runs/nope/files/x', '/runs/nope/report.json',
            '/runs/nope/download.tar', '/runs/%00', '/runs/a%20b', "/runs/#{'a' * 5000}"].freeze
    FILES = ['../meta.json', '..%2Fmeta.json', '%2e%2e/input/spec.yaml', 'nope', '%00', 'x/..', '.'].freeze
    NO_PATHS = "openapi: 3.0.3\ninfo: {title: X, version: '1'}\npaths: {}\n"
    EXAMPLE = 'examples/specs/novapay.yaml'

    def route_cases
      good = run_id(post('/runs', 'example' => EXAMPLE, 'verify' => '0'))
      bad = run_id(post('/runs', 'spec_text' => NO_PATHS))
      @h.check('url:foreign') { foreign_urls }
      @h.check('url:files') { file_paths(good) }
      @h.check('url:steps_on_failed_run') { steps(bad) }
      @h.check('http:methods') { methods(good) }
      @h.check('http:huge_upload') { huge_upload }
      @h.check('http:weird_query') { weird_query(good) }
      @h.check('http:bad_encoding_params') { bad_encoding }
      @h.check('http:disk_state') { disk_state }
    end

    private

    def foreign_urls
      URLS.each do |u|
        ok!(get(u), "GET #{u[0, 40]}")
        ok!(post(u), "POST #{u[0, 40]}")
      end
    end

    def file_paths(id)
      FILES.each do |f|
        res = ok!(get("/runs/#{id}/files/#{f}"), "files/#{f}")
        raise "leaked meta.json via files/#{f}" if res.body.include?('"spec_name"')
      end
    end

    def steps(id)
      %w[spec e2e].each do |step|
        ok!(post("/runs/#{id}/#{step}"), "POST #{step}")
        ok!(get("/runs/#{id}"), 'GET run')
      end
      post("/runs/#{id}/delete")
      raise 'deleted run is not 404' unless get("/runs/#{id}").status == 404
    end

    def methods(id)
      urls = ['/', "/runs/#{id}", "/runs/#{id}/report.json", "/runs/#{id}/download.tar", "/runs/#{id}/files/report.txt"]
      urls.product(%w[HEAD PUT PATCH DELETE OPTIONS]).each { |u, m| ok!(@client.request(m, u), "#{m} #{u}") }
    end

    def huge_upload
      res = ok!(post('/runs', 'spec' => upload('a' * (21 * 1024 * 1024), 'big.yaml')), 'huge upload')
      return if res.status == 200 && res.body.include?('too large')

      raise "huge upload: HTTP #{res.status} without 'too large'"
    end

    def weird_query(id)
      ["/runs/#{id}?tab=%00", "/runs/#{id}?tab[]=1", "/runs/#{id}?tab[a]=1", "/?x=#{'a' * 100_000}",
       "/runs/#{id}/files/report.txt?download[]=1", "/runs/#{id}/files/report.txt?download=%ff"]
        .each { |u| ok!(get(u), u[0, 60]) }
    end

    def bad_encoding
      ok!(post('/runs', 'provider' => "\xff\xfe".b, 'example' => EXAMPLE, 'verify' => '0'), 'provider bytes')
      ok!(post('/runs', 'include_paths' => "\xff".b, 'example' => EXAMPLE, 'verify' => '0'), 'include_paths bytes')
    end

    # Каталог прогона портится «под ногами»: out/ удалён, meta.json и report.json — мусор.
    def disk_state
      id = run_id(post('/runs', 'example' => EXAMPLE, 'verify' => '0'))
      FileUtils.rm_rf(File.join(@root, id, 'out'))
      visit_run(id)
      ['not json', '[]'].each do |meta|
        File.write(File.join(@root, id, 'meta.json'), meta)
        ok!(get("/runs/#{id}"), "meta.json = #{meta}")
      end
      File.write(File.join(@root, id, 'report.json'),
                 '{"endpoints": "x", "amount": {"path": "s"}, "errors": {"rows": [{"status": null}, {"status": 1}]}}')
      ok!(get("/runs/#{id}"), 'broken report.json')
    end
  end
end
