Gem::Specification.new do |s|
  s.name = 'rbg'
  s.version = '0.9.2'
  s.summary = 'Ruby Backgrounder allows multiple copies of ruby scripts to be run in the background and restarted'
  
  s.platform = Gem::Platform::RUBY
  
  s.files = Dir.glob("{bin,lib}/**/*")
  s.require_path = 'lib'
  s.has_rdoc = false
  s.bindir = "bin"
  s.executables = ['rbg']
  
  s.author = 'Charlie Smurthwaite'
  s.email = 'charlie@atechmedia.com'
  s.homepage = 'http://www.atechmedia.com'
end

