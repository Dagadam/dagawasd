# DagaWASD — client del ponte per Claude (lib/bridge.rb).
# Non viene installato in SketchUp: lo usa Claude Code dalla riga di comando.
#
#   ruby tools/su.rb ping
#   ruby tools/su.rb eval script.rb [--op "Nome operazione"]
#   ruby tools/su.rb eval -e "ents.add_line([0,0,0], [1.m,0,0])"
#   ruby tools/su.rb eval -            (codice da stdin)
#   ruby tools/su.rb image vista.png [larghezza altezza]
#
# Legge porta e token da %APPDATA%\DagaWASD\bridge.json, scritto da
# SketchUp quando il ponte è acceso (Sistema › Ponte Claude).
# Esce con 0 se tutto è andato bene, 1 per un errore nel codice o nel
# collegamento, 2 per un uso sbagliato.
require 'json'
require 'net/http'

def die(msg, code = 1)
  warn "su.rb: #{msg}"
  exit code
end

info_path = File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'bridge.json')
die("#{info_path} non esiste: accendi il ponte in DagaWASD (Sistema › Ponte Claude)") unless File.exist?(info_path)
info = JSON.parse(File.read(info_path, encoding: 'UTF-8')) rescue die("#{info_path} illeggibile")

def request(info, req)
  req['X-Token'] = info['token']
  Net::HTTP.start('127.0.0.1', info['port'], open_timeout: 3, read_timeout: 600) { |h| h.request(req) }
rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout
  die("SketchUp non risponde sulla porta #{info['port']}: è aperto, col ponte acceso?")
end

cmd = ARGV.shift
case cmd
when 'ping'
  res = request(info, Net::HTTP::Get.new('/ping'))
  puts res.body.force_encoding('UTF-8')
  exit(res.code == '200' ? 0 : 1)

when 'eval'
  op = nil
  if (i = ARGV.index('--op'))
    op = ARGV[i + 1]
    ARGV.slice!(i, 2)
  end
  src = ARGV.shift or die('manca il codice: file, -e "codice" oppure - per stdin', 2)
  code = case src
         when '-e' then ARGV.shift or die('-e senza codice', 2)
         when '-'  then $stdin.read
         else File.read(src, encoding: 'UTF-8')
         end
  path = '/eval' + (op ? "?op=#{URI.encode_www_form_component(op)}" : '')
  req = Net::HTTP::Post.new(path)
  req['Content-Type'] = 'text/plain; charset=utf-8'
  req.body = code.encode('UTF-8')
  res = request(info, req)
  body = JSON.parse(res.body.force_encoding('UTF-8')) rescue { 'ok' => false, 'error' => res.body }
  out = body.delete('output').to_s
  puts out unless out.empty?
  puts JSON.pretty_generate(body)
  exit(body['ok'] ? 0 : 1)

when 'image'
  file = ARGV.shift or die('manca il file di destinazione (.png)', 2)
  w, h = ARGV.shift.to_i, ARGV.shift.to_i
  q = w.positive? && h.positive? ? "?w=#{w}&h=#{h}" : ''
  res = request(info, Net::HTTP::Get.new("/image#{q}"))
  die(res.body.force_encoding('UTF-8')) unless res.code == '200'
  File.binwrite(file, res.body)
  puts "#{file} (#{res.body.bytesize} byte)"

else
  die("comando sconosciuto: #{cmd.inspect} — usa ping, eval o image", 2)
end
