#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "pathname"
require "rubygems/version"
require "uri"

PACKAGE_NAME = "vyspec"
FORMULA_REFERENCE = ENV.fetch("VYSPEC_FORMULA_REFERENCE", "vyspec/tap/vyspec")
SEMANTIC_VERSION = /\A\d+\.\d+\.\d+\z/
PYPI_HOST = "pypi.org"
PYPI_FILES_HOST = "files.pythonhosted.org"
PLAYWRIGHT_SOURCE_HOST = "github.com"

def fetch(uri, redirects_remaining: 5)
  raise "Too many redirects while requesting #{uri}" if redirects_remaining.negative?

  request = Net::HTTP::Get.new(uri)
  request["Accept"] = "application/json"
  request["User-Agent"] = "Vyspec-Homebrew-Updater"

  response = Net::HTTP.start(
    uri.hostname,
    uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: 15,
    read_timeout: 60,
  ) { |http| http.request(request) }

  case response
  when Net::HTTPSuccess
    response.body
  when Net::HTTPRedirection
    location = response.fetch("location")
    fetch(URI.join(uri, location), redirects_remaining: redirects_remaining - 1)
  else
    raise "Request for #{uri} failed with HTTP #{response.code}"
  end
end

def replace_once!(contents, pattern, replacement, label)
  matches = contents.scan(pattern)
  raise "Expected exactly one #{label}; found #{matches.length}" unless matches.length == 1

  contents.sub!(pattern, replacement)
end

def write_output(name, value)
  output_path = ENV["GITHUB_OUTPUT"]
  return if output_path.nil? || output_path.empty?

  File.open(output_path, "a") { |output| output.puts("#{name}=#{value}") }
end

requested_version = ENV.fetch("VYSPEC_VERSION", "").strip
unless requested_version.empty? || SEMANTIC_VERSION.match?(requested_version)
  raise "VYSPEC_VERSION must use MAJOR.MINOR.PATCH"
end

metadata_uri = if requested_version.empty?
  URI("https://#{PYPI_HOST}/pypi/#{PACKAGE_NAME}/json")
else
  URI("https://#{PYPI_HOST}/pypi/#{PACKAGE_NAME}/#{requested_version}/json")
end
metadata = JSON.parse(fetch(metadata_uri))
version = metadata.fetch("info").fetch("version")
raise "PyPI returned an invalid version: #{version.inspect}" unless SEMANTIC_VERSION.match?(version)
if !requested_version.empty? && requested_version != version
  raise "PyPI returned #{version.inspect} for requested version #{requested_version.inspect}"
end

sdists = metadata.fetch("urls").select { |file| file.fetch("packagetype") == "sdist" }
raise "Expected exactly one source distribution; found #{sdists.length}" unless sdists.length == 1

sdist = sdists.fetch(0)
sdist_uri = URI(sdist.fetch("url"))
unless sdist_uri.scheme == "https" && sdist_uri.host == PYPI_FILES_HOST &&
       sdist.fetch("filename") == "#{PACKAGE_NAME}-#{version}.tar.gz"
  raise "PyPI returned an unexpected source distribution URL"
end
sdist_sha256 = sdist.fetch("digests").fetch("sha256")
raise "PyPI returned an invalid source distribution digest" unless /\A[0-9a-f]{64}\z/.match?(sdist_sha256)

requirements = metadata.fetch("info").fetch("requires_dist")
playwright_requirements = requirements.each_with_object([]) do |requirement, versions|
  match = requirement.match(/\Aplaywright==([0-9]+\.[0-9]+\.[0-9]+)(?:\s|;|\z)/)
  versions << match[1] unless match.nil?
end
unless playwright_requirements.length == 1
  raise "Vyspec must declare exactly one exact Playwright version"
end
playwright_version = playwright_requirements.fetch(0)
playwright_uri = URI(
  "https://#{PLAYWRIGHT_SOURCE_HOST}/microsoft/playwright-python/archive/refs/tags/" \
  "v#{playwright_version}.tar.gz",
)
playwright_sha256 = Digest::SHA256.hexdigest(fetch(playwright_uri))

repository_root = Pathname(__dir__).parent
formula_path = repository_root/"Formula/vyspec.rb"
original_formula = formula_path.read
current_version = original_formula[/vyspec-(\d+\.\d+\.\d+)\.tar\.gz/, 1]
raise "Could not read the current Vyspec formula version" if current_version.nil?

current = Gem::Version.new(current_version)
target = Gem::Version.new(version)
raise "Refusing to downgrade Vyspec from #{current} to #{target}" if target < current

if target == current && ENV["VYSPEC_FORCE_UPDATE"] != "1"
  puts "Vyspec #{version} is already current."
  write_output("changed", "false")
  write_output("version", version)
  exit 0
end

playwright_block_pattern = %r{\n  \# Playwright does not publish a source distribution to PyPI\.\n  resource "playwright" do\n    url "[^"]+"\n    sha256 "[0-9a-f]{64}"\n  end\n}
playwright_blocks = original_formula.scan(playwright_block_pattern)
unless playwright_blocks.length == 1
  raise "Expected exactly one managed Playwright resource; found #{playwright_blocks.length}"
end

updated_formula = original_formula.dup
replace_once!(
  updated_formula,
  /^  url "https:\/\/files\.pythonhosted\.org\/[^\n]+\/vyspec-\d+\.\d+\.\d+\.tar\.gz"$/,
  %(  url "#{sdist_uri}"),
  "Vyspec source URL",
)
replace_once!(
  updated_formula,
  /(^  url "https:\/\/files\.pythonhosted\.org\/[^\n]+\/vyspec-#{Regexp.escape(version)}\.tar\.gz"\n)  sha256 "[0-9a-f]{64}"$/,
  %(\\1  sha256 "#{sdist_sha256}"),
  "Vyspec source digest",
)

playwright_block = <<~RUBY.chomp
  # Playwright does not publish a source distribution to PyPI.
  resource "playwright" do
    url "#{playwright_uri}"
    sha256 "#{playwright_sha256}"
  end
RUBY
playwright_block = playwright_block.lines.map { |line| "  #{line}" }.join

updated_formula.sub!(playwright_block_pattern, "\n")
formula_path.write(updated_formula)

begin
  command = [
    "brew",
    "update-python-resources",
    FORMULA_REFERENCE,
    "--ignore-main-package-cooldown",
  ]
  raise "Homebrew could not update Python resources" unless system(*command)

  generated_formula = formula_path.read
  resource_anchor = /(^  pypi_packages [^\n]+\n                extra_packages: [^\n]+\n)/
  replace_once!(
    generated_formula,
    resource_anchor,
    "\\1\n#{playwright_block}",
    "Python package declaration",
  )
  formula_path.write(generated_formula)
rescue StandardError
  formula_path.write(original_formula)
  raise
end

puts "Updated Vyspec formula from #{current_version} to #{version}."
write_output("changed", "true")
write_output("version", version)
