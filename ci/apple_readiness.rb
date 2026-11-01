require 'openssl'
require 'json'
require 'base64'
require 'net/http'
require 'uri'

def b64(data)
  Base64.urlsafe_encode64(data, padding: false)
end
begin
  private_key = OpenSSL::PKey.read(Base64.strict_decode64(ENV.fetch('ASC_PRIVATE_KEY_B64')))
  now = Time.now.to_i
  header = b64(JSON.generate({alg: 'ES256', kid: '9X6UGZYBYR', typ: 'JWT'}))
  payload = b64(JSON.generate({iss: '54a3742f-c62d-468e-a2ae-70e0d8aff797',
                              iat: now, exp: now+300, aud: 'appstoreconnect-v1'}))
  unsigned = header+'.'+payload
  der = private_key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(unsigned))
  values = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
  raise 'signature shape' unless values.all? { |v| v.bytesize == 32 }
  token = unsigned+'.'+b64(values.join)
  queries = {
    bundle_ids: '/v1/bundleIds?filter[identifier]=dev.nextaura.turkishscenes',
    apps: '/v1/apps?filter[bundleId]=dev.nextaura.turkishscenes',
    distribution_certificate: '/v1/certificates/8D6ULMGL7T'
  }
  results = {}
  queries.each do |name,path|
    uri = URI('https://api.appstoreconnect.apple.com'+path)
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = 'Bearer '+token
    response = Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:30,read_timeout:30) { |http| http.request(req) }
    raise "request failed #{name} status #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    parsed = JSON.parse(response.body)
    records = parsed['data'].is_a?(Array) ? parsed['data'] : [parsed['data']]
    results[name] = records.map do |item|
      attrs = item.fetch('attributes',{})
      {id: item['id'], identifier: attrs['identifier'], name: attrs['name'],
       bundleId: attrs['bundleId'], certificateType: attrs['certificateType'],
       expirationDate: attrs['expirationDate']}
    end
  end
  puts JSON.pretty_generate({mode:'READ_ONLY',results:results})
rescue => error
  # Never expose HTTP bodies, authentication material, or private-key parse details.
  warn "Apple readiness did not complete (#{error.class}). No mutation was attempted."
  exit 1
end
