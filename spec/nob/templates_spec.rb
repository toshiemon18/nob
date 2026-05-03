require "spec_helper"

RSpec.describe Nob::Templates do
  describe Nob::Templates::UndefinedVariable do
    it "inherits from Nob::Error" do
      expect(described_class.ancestors).to include(Nob::Error)
    end
  end

  describe Nob::Templates::ParseError do
    it "inherits from Nob::Error" do
      expect(described_class.ancestors).to include(Nob::Error)
    end
  end

  describe Nob::Templates::Literal do
    it "is included in Token" do
      expect(described_class.new("x")).to be_a(Nob::Templates::Token)
    end

    it "compares by text" do
      expect(described_class.new("x")).to eq(described_class.new("x"))
      expect(described_class.new("x")).not_to eq(described_class.new("y"))
    end
  end

  describe Nob::Templates::Variable do
    it "is included in Token" do
      expect(described_class.new(Object.new)).to be_a(Nob::Templates::Token)
    end

    it "compares by operator" do
      op1 = Nob::Templates::Operators::Date.new("%Y")
      op2 = Nob::Templates::Operators::Date.new("%Y")
      op3 = Nob::Templates::Operators::Date.new("%m")
      expect(described_class.new(op1)).to eq(described_class.new(op2))
      expect(described_class.new(op1)).not_to eq(described_class.new(op3))
    end
  end
end
