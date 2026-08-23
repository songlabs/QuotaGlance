#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "uri"

$stdout.sync = true

options = {}
OptionParser.new do |parser|
  parser.on("--key-path PATH") { |value| options[:key_path] = value }
  parser.on("--key-id ID") { |value| options[:key_id] = value }
  parser.on("--issuer-id ID") { |value| options[:issuer_id] = value }
  parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
  parser.on("--build-number NUMBER") { |value| options[:build_number] = value }
  parser.on("--group-name NAME") { |value| options[:group_name] = value }
end.parse!

missing = %i[key_path key_id issuer_id bundle_id build_number group_name].reject { |key| options[key] }
abort "Missing options: #{missing.join(', ')}" unless missing.empty?

def base64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

def token(options)
  header = base64url(JSON.generate(alg: "ES256", kid: options[:key_id], typ: "JWT"))
  payload = base64url(JSON.generate(iss: options[:issuer_id], iat: Time.now.to_i, exp: Time.now.to_i + 1_200, aud: "appstoreconnect-v1"))
  signing_input = "#{header}.#{payload}"
  key = OpenSSL::PKey.read(File.read(options[:key_path]))
  decoded = OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest::SHA256.new, signing_input))
  raw_signature = decoded.value.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
  "#{signing_input}.#{base64url(raw_signature)}"
end

def request(options, method, path, body = nil)
  uri = URI(path.start_with?("http") ? path : "https://api.appstoreconnect.apple.com#{path}")
  request_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{token(options)}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  return response.body.empty? ? {} : JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

  abort "App Store Connect API #{method.upcase} #{path} failed (#{response.code}): #{response.body}"
end

def one_record!(response, description)
  records = response.fetch("data")
  abort "Could not uniquely find #{description} (found #{records.length})" unless records.length == 1
  records.first
end

app_query = URI.encode_www_form("filter[bundleId]" => options[:bundle_id], "limit" => "2")
app = one_record!(request(options, :get, "/v1/apps?#{app_query}"), "app #{options[:bundle_id]}")
group_query = URI.encode_www_form("filter[app]" => app.fetch("id"), "filter[name]" => options[:group_name], "limit" => "2")
group_query = "#{group_query}&#{URI.encode_www_form('fields[betaGroups]' => 'name,isInternalGroup,hasAccessToAllBuilds')}"
group = one_record!(request(options, :get, "/v1/betaGroups?#{group_query}"), "beta group #{options[:group_name]}")

group_attributes = group.fetch("attributes")
if group_attributes.fetch("isInternalGroup") && group_attributes.fetch("hasAccessToAllBuilds")
  puts "Internal group has access to all builds; explicit assignment is not required."
  exit
end

build = nil
120.times do |attempt|
  build_query = URI.encode_www_form("filter[app]" => app.fetch("id"), "filter[version]" => options[:build_number], "limit" => "2")
  records = request(options, :get, "/v1/builds?#{build_query}").fetch("data")
  unless records.empty?
    candidate = records.first
    state = candidate.fetch("attributes").fetch("processingState")
    abort "TestFlight processing failed for build #{options[:build_number]}" if state == "FAILED"
    if state == "VALID"
      build = candidate
      break
    end
    puts "Build #{options[:build_number]} is #{state}; waiting (attempt #{attempt + 1}/120)."
  else
    puts "Build #{options[:build_number]} is not visible yet; waiting (attempt #{attempt + 1}/120)."
  end
  sleep 30
end
abort "Timed out waiting for TestFlight build #{options[:build_number]}" unless build

build_assigned = false
group_builds_path = "/v1/betaGroups/#{group.fetch('id')}/relationships/builds?limit=200"
while group_builds_path
  response = request(options, :get, group_builds_path)
  if response.fetch("data").any? { |record| record.fetch("id") == build.fetch("id") }
    build_assigned = true
    break
  end
  group_builds_path = response.fetch("links", {})["next"]
end

if build_assigned
  puts "Build #{options[:build_number]} already belongs to #{options[:group_name]}; explicit assignment is not required."
  exit
end

request(
  options,
  :post,
  "/v1/betaGroups/#{group.fetch('id')}/relationships/builds",
  data: [{ type: "builds", id: build.fetch("id") }]
)
puts "Assigned build #{options[:build_number]} to #{options[:group_name]}."
