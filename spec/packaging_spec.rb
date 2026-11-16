# frozen_string_literal: true

RSpec.describe "the packaged gem" do
  let(:files) { Gem::Specification.load(File.expand_path("../mu-action.gemspec", __dir__)).files }

  it "contains the library" do
    library = Dir.chdir(File.expand_path("..", __dir__)) { Dir["lib/mu/**/*.rb"] }

    expect(files).to include(*library)
  end

  it "contains nothing else than the library and the docs" do
    expect(files.grep_v(%r{\Alib/mu/})).to contain_exactly("CHANGELOG.md", "LICENSE.txt", "README.md")
  end
end
