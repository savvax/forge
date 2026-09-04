# frozen_string_literal: true

module Forge
  module Renderers
    # report.txt — тот же текст, что и stdout команды generate; пути вывода относительно самого каталога
    # (никаких путей машины в выходных файлах — детерминизм).
    module ReportFile
      module_function

      def write(out_dir, text)
        path = File.join(out_dir, 'report.txt')
        local = text.gsub("./#{out_dir.delete_prefix('./')}/", './')
        File.write(path, local.end_with?("\n") ? local : "#{local}\n")
        path
      end
    end
  end
end
