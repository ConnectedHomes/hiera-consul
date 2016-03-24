# Hiera Consul

A simple interface for delivering puppet hiera configuraton via a consul cluster.

## Installation

    $ gem install bgch-hiera-consul

## Usage

Add the following blocks to your hiera.yaml:

<pre>
:backends:
  - consul

:consul:
  :host: &lt;address&gt;
  :port: 8500
  :paths:
    - /v1/kv/configuration/%{::environment}
    - /v1/kv/configuration/common
  :autoconvert:
    - yaml
    - json
</pre>

Other backends can be above or below consul.

There are various other options to the consul block.  Autoconvert is optional, and without it all values will be treated as strings.

The hiera_hash and hiera_array functions work correctly.

You may add more paths as you see fit, using hiera interpolation to create dynamic paths based on facts.

## Derivation

Built substantially on top of lynxman's hiera-consul, with a more complete solution for structured data.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ConnectedHomes/bgch-hiera-consul. 

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

