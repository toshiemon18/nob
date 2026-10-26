require "spec_helper"

RSpec.describe Nob::TimeFormat do
  let(:now) { Time.new(2026, 3, 7, 9, 5, 2) }

  def format(fmt) = described_class.new(fmt).format(now)

  describe "a format containing %" do
    it "is read as strftime" do
      expect(format("%Y/%m/%d %H:%M")).to(eq("2026/03/07 09:05"))
    end
  end

  describe "a format without %" do
    it "is read as moment" do
      expect(format("YYYY-MM-DD")).to(eq("2026-03-07"))
    end

    it "supports every listed token" do
      expect(format("YYYY YY MM M DD D HH H mm ss")).to(eq("2026 26 03 3 07 7 09 9 05 02"))
    end

    it "matches the longest token first" do
      expect(format("YYYYMMDD")).to(eq("20260307"))
    end

    it "keeps characters other than ASCII letters" do
      expect(format("YYYY年M月D日 (HH:mm)")).to(eq("2026年3月7日 (09:05)"))
    end

    it "keeps text in brackets as it is" do
      expect(format("[Week of] YYYY-MM-DD[T]HH")).to(eq("Week of 2026-03-07T09"))
    end

    it "builds a nested path" do
      expect(format("YYYY/MM/YYYY-MM-DD")).to(eq("2026/03/2026-03-07"))
    end

    it "returns an empty string for an empty format" do
      expect(format("")).to(eq(""))
    end
  end

  describe "an unsupported moment format" do
    it "rejects a token outside the list" do
      expect { described_class.new("dddd YYYY") }
        .to(raise_error(Nob::TimeFormat::UnsupportedToken, "unsupported format token: dddd"))
    end

    # moment では MMMM は月名、MMM は月の略称、DDDD は年内の日。MM や DD を並べたものと読まない
    it "rejects a longer run of a token's letter" do
      ["MMMM", "MMM", "DDDD", "YYYYY", "HHH"].each do |fmt|
        expect { described_class.new(fmt) }
          .to(raise_error(Nob::TimeFormat::UnsupportedToken, "unsupported format token: #{fmt}"))
      end
    end

    it "names the whole run of letters when only part of it is a token" do
      expect { described_class.new("Do MMMM") }
        .to(raise_error(Nob::TimeFormat::UnsupportedToken, "unsupported format token: Do"))
    end

    it "rejects a single m, which moment reads as minutes without padding" do
      expect { described_class.new("H:m") }.to(
        raise_error(Nob::TimeFormat::UnsupportedToken, "unsupported format token: m")
      )
    end

    it "rejects a bracket that is not closed" do
      expect { described_class.new("[YYYY") }
        .to(raise_error(Nob::TimeFormat::UnsupportedToken, "unterminated [ in format: [YYYY"))
    end
  end
end
