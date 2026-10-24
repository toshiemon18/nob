module Nob
  class Config
    # nob が読む設定キーの一覧
    module Keys
      VAULT = Key.new(section: nil, name: "vault", default: nil)
      DAILY_BASE_PATH = Key.new(section: "dailyNote", name: "basePath", default: "daily/")
      DAILY_FILE_NAME_FORMAT = Key.new(section: "dailyNote", name: "fileNameFormat", default: "%Y-%m-%d")
      DAILY_TEMPLATE = Key.new(section: "dailyNote", name: "template", default: nil)
      NOTE_TEMPLATE = Key.new(section: "note", name: "template", default: nil)
    end
  end
end
