
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "sensu-plugin-collectd/version"

Gem::Specification.new do |spec|
  spec.name          = "sensu-plugin-collectd"
  spec.version       = Sensu::Plugin::Collectd::VER_STRING
  spec.authors       = ["Pilar Gomez"]
  spec.email         = ["mp.gomezmoya@gmail.com"]

  spec.summary       = 'Sensu plugin to pull metrics from the collectd socket'
  spec.homepage      = "https://github.com/mpgomez/sensu-plugin-collectd"
  spec.executables   = Dir.glob('bin/**/*.rb').map { |file| File.basename(file) }
  spec.files         = Dir.glob('{bin,lib}/**/*') + %w[LICENSE README.md CHANGELOG.md]
  spec.license       = 'MIT'
  spec.require_paths = ["lib"]
  spec.platform      = Gem::Platform::RUBY
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})

  spec.add_runtime_dependency "sensu-plugin", "~> 1.2"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.4"
end
