module Sensu
  module Plugin
    module Collectd
      MAJOR = 0
      MINOR = 1
      PATCH = 1

      VER_STRING = [MAJOR, MINOR, PATCH].compact.join('.')
    end
  end
end
