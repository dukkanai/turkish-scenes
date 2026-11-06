# Read-only verification of the exact build just uploaded. Never adds testers or groups.
require 'openssl'
require 'json'
require 'base64'
require 'net/http'
require 'uri'

KEY_ID = '9X6UGZYBYR'
ISSUER = '54a3742f-c62d-468e-a2ae-70e0d8aff797'
BUNDLE = 'dev.nextaura.turkishscenes'
def b64(data)
  Base64.urlsafe_encode64(data, padding: false)
end
def get(path, parameters, key)
  now = Time.now.to_i
  unsigned = b64(JSON.generate({alg: 'ES256', kid: KEY_ID, typ: 'JWT'})) + '.' +
    b64(JSON.generate({iss: ISSUER, iat: now, exp: now + 120, aud: 'appstoreconnect-v1'}))
  der = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(unsigned))
  parts = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
  raise 'invalid signature shape' unless parts.all? { |v| v.bytesize == 32 }
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  uri.query = URI.encode_www_form(parameters) unless parameters.empty?
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = 'Bearer ' + unsigned + '.' + b64(parts.join)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |h| h.request(req) }
  raise "Apple API status #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end
begin
  build_number = ENV.fetch('TURKISH_EXPECTED_BUILD')
  raise 'invalid build number' unless build_number.match?(/\A\d+\.\d+\z/)
  key_file = File.join(ENV.fetch('PRIVATE_DIR'), "AuthKey_#{KEY_ID}.p8")
  key = OpenSSL::PKey.read(File.read(key_file))
  apps = get('/v1/apps', {'filter[bundleId]' => BUNDLE, 'limit' => '2'}, key).fetch('data')
  raise 'app not uniquely resolved' unless apps.length == 1
  app_id = apps.first.fetch('id')
  final = {mode: 'READ_ONLY', status: 'PROCESSING_PENDING', build: build_number, bundle: BUNDLE}
  12.times do |attempt|
    builds = get('/v1/builds', {'filter[app]' => app_id, 'filter[version]' => build_number, 'include' => 'preReleaseVersion', 'limit' => '10'}, key)
    candidates = builds.fetch('data')
    raise 'ambiguous build result' if candidates.length > 1
    if candidates.length == 1
      build = candidates.first
      attrs = build.fetch('attributes')
      final[:build_id] = build.fetch('id')
      final[:processing_state] = attrs['processingState']
      version_id = build.dig('relationships', 'preReleaseVersion', 'data', 'id')
      version = (builds['included'] || []).find { |v| v['id'] == version_id }
      final[:marketing_version] = version&.dig('attributes', 'version')
      if ['FAILED', 'INVALID'].include?(attrs['processingState'])
        final[:status] = 'PROCESSING_FAILED'
        puts JSON.pretty_generate(final)
        exit 1
      end
      if attrs['processingState'] == 'VALID'
        detail = get("/v1/builds/#{build.fetch('id')}/buildBetaDetail", {}, key).fetch('data').fetch('attributes')
        final[:internal_state] = detail['internalBuildState']
        groups = get('/v1/betaGroups', {'filter[app]' => app_id, 'limit' => '200'}, key).fetch('data')
        allowed = groups.select { |g| g.dig('attributes', 'isInternalGroup') }
        matching = allowed.select do |group|
          group.dig('attributes', 'hasAccessToAllBuilds') ||
            get("/v1/betaGroups/#{group.fetch('id')}/builds", {'limit' => '200'}, key).fetch('data').any? { |b| b['id'] == build['id'] }
        end
        final[:internal_groups] = matching.map { |g| {id: g['id'], name: g.dig('attributes', 'name')} }
        if detail['internalBuildState'] == 'IN_BETA_TESTING' && !matching.empty?
          final[:status] = 'AVAILABLE_FOR_INTERNAL_TESTING'
          puts JSON.pretty_generate(final)
          exit 0
        end
        final[:status] = 'PROCESSED_AVAILABILITY_PENDING'
      end
    end
    puts JSON.generate({check: attempt + 1, build: build_number, status: final[:status], processing_state: final[:processing_state]})
    sleep 30 if attempt < 11
  end
  puts JSON.pretty_generate(final)
  puts 'Upload is not repeated. Apple processing or tester availability still needs a later read-only check.'
rescue => error
  warn "Read-only TestFlight verification did not complete (#{error.class}). Upload outcome must be inspected before any retry."
  exit 1
end
