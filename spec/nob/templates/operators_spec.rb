require "spec_helper"

RSpec.describe Nob::Templates::Operators do
  describe ".build" do
    it "constructs Title for name 'title'" do
      op = described_class.build(name: "title", fmt: nil)
      expect(op).to eq(Nob::Templates::Operators::Title.new(nil))
    end

    it "constructs Date with fmt" do
      op = described_class.build(name: "date", fmt: "%Y/%m/%d")
      expect(op).to eq(Nob::Templates::Operators::Date.new("%Y/%m/%d"))
    end

    it "constructs Time without fmt" do
      op = described_class.build(name: "time", fmt: nil)
      expect(op).to eq(Nob::Templates::Operators::Time.new(nil))
    end

    it "constructs Id without fmt" do
      op = described_class.build(name: "id", fmt: nil)
      expect(op).to eq(Nob::Templates::Operators::Id.new(nil))
    end

    it "raises UndefinedVariable for unknown name" do
      expect { described_class.build(name: "foo", fmt: nil) }.to raise_error(
        Nob::Templates::UndefinedVariable, /unknown variable: foo/
      )
    end

    it "propagates UndefinedVariable from operator constructor (e.g., title with fmt)" do
      expect { described_class.build(name: "title", fmt: "x") }.to raise_error(
        Nob::Templates::UndefinedVariable, /title does not accept format/
      )
    end

    it "rejects a name with mixed case (Title) as UndefinedVariable" do
      expect { described_class.build(name: "Title", fmt: nil) }.to raise_error(
        Nob::Templates::UndefinedVariable, /unknown variable: Title/
      )
    end
  end
end
