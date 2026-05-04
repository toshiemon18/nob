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

    context "with dynamic Operator subclasses (1-file extension contract)" do
      after do
        if described_class.const_defined?(:Foo, false)
          described_class.send(:remove_const, :Foo)
        end
      end

      it "constructs an Operator class added under Operators without editing the dispatch table" do
        described_class.const_set(:Foo, Class.new(Nob::Templates::Operators::Base) {
          def call(title:, now:) = "foo"
        })

        op = described_class.build(name: "foo", fmt: nil)

        expect(op).to be_a(described_class.const_get(:Foo))
      end
    end

    it "rejects a name with mixed case (Title) as UndefinedVariable" do
      expect { described_class.build(name: "Title", fmt: nil) }.to raise_error(
        Nob::Templates::UndefinedVariable, /unknown variable: Title/
      )
    end

    it "refuses Base itself as a target operator" do
      expect { described_class.build(name: "base", fmt: nil) }.to raise_error(
        Nob::Templates::UndefinedVariable, /unknown variable: base/
      )
    end
  end
end
