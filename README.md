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

## Examples

NB Consul also provides a gui at ``http://<address>:8500/ui`` if you prefer.

### Classes

Hiera always attempts to load a hiera_array of 'classes'.

To include a class called 'users' in all environments (per the consul block above):

    curl -X PUT -d '["users"]' http://<address>:8500/v1/kv/configuration/common/classes

### Hiera functions

If you load a list of users with hiera(users, []) for example.

To include classes called users and groups in all environments:

    curl -X PUT -d '["users", "groups"]' http://<address>:8500/v1/kv/configuration/common/classes

To include (only) support users in the prod environment:

    curl -X PUT -d '["support_jim", "support_sally"]' http://<address>:8500/v1/kv/configuration/prod/users

To include (only) dev users in the dev environment:

    curl -X PUT -d '["dev_saket", "dev_david"]' http://<address>:8500/v1/kv/configuration/dev/users

To include (only) ops users in all environments:

    curl -X PUT -d '["ops_justin", "ops_cathy"]' http://<address>:8500/v1/kv/configuration/common/users

#### Class Parameters

Once Hiera has found a list of classes, it will attempt to prepopulate the class parameters.

To include structured data from a file:

    curl -X PUT -d @<myconfigfile> http://<address>:8500/v1/kv/configuration/common/myconfig

## Derivation

Built substantially on top of lynxman's hiera-consul, with a more complete solution for structured data.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ConnectedHomes/bgch-hiera-consul. 

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

