package Dist::Zilla::Role::PluginBundle::Merged;

# VERSION
# ABSTRACT: Mindnumbingly easy way to create a PluginBundle

use MooseX::Role::Parameterized;
use sanity;

use Class::Load;
use Storable 'dclone';
use Scalar::Util 'blessed';

use String::RewritePrefix 0.005 rewrite => {
   -as => '_section_class',
   prefixes => {
      ''  => 'Dist::Zilla::Plugin::',
      '@' => 'Dist::Zilla::PluginBundle::',
      '=' => ''
   },
};
use String::RewritePrefix 0.005 rewrite => {
   -as => '_plugin_name',
   prefixes => {
      'Dist::Zilla::Plugin::'       => '',
      'Dist::Zilla::PluginBundle::' => '@',
      '' => '=',
   },
};

with 'Dist::Zilla::Role::PluginBundle::Easy';

parameter mv_plugins => (
   isa      => 'ArrayRef[Str]',
   required => 0,
   default  => sub { [] },
);

role {
   my $p = shift;

   method mvp_multivalue_args => sub {
      my @list = @{ $p->mv_plugins };
      return unless @list;

      my %multi;
      foreach my $name (@list) {
         my $class = _section_class($name);
         Class::Load::load_class($class);
         @multi{$class->mvp_multivalue_args} = () if $class->can('mvp_multivalue_args');
      }

      return keys %multi;
   };

   method add_merged => sub {
      my $self = shift;
      my @list = @_;
      my $arg = $self->payload;

      my @config;
      foreach my $name (@list) {
         if (my $ref = ref $name) {
            if    ($ref eq 'HASH')  { $arg = $name; }
            elsif ($ref eq 'ARRAY') { $self->add_plugins($name); }
            else                    { die "Cannot pass $ref to add_merged"; }

            next;
         }

         my $class = _section_class($name);
         Class::Load::load_class($class);

         # check mv_plugins list to make sure the class was passed
         unless (grep { $_ eq $name } @{ $p->mv_plugins }) {
            warn $self->_fake_log_prefix." $name has MVPs, but was never passed in the mv_plugins list\n"
               if ($class->can('mvp_multivalue_args') and scalar($class->mvp_multivalue_args));
         }

         # handle mvp_aliases
         my %aliases = ();
         %aliases = %{$class->mvp_aliases} if $class->can('mvp_aliases');

         if ($name =~ /^\@/) {
            # just give it everything, since we can't separate them out
            $self->add_bundle($name => $arg);
         }
         else {
            my %payload;
            foreach my $k (keys %$arg) {
               $payload{$k} = $arg->{$k} if $class->can( $aliases{$k} || $k );
            }
            $self->add_plugins([ "=$class" => $name => \%payload ]);
         }
      }
   };

   method config_rename => sub {
      my $self     = shift;
      my $payload  = $self->payload;
      my $args     = dclone($payload);
      my $chg_list = ref $_[0] ? $_[0] : { @_ };

      foreach my $key (keys %$chg_list) {
         my $new_key = $chg_list->{$key};
         my $val     = delete $args->{$key};
         next unless ($new_key);
         $args->{$new_key} = $val if (defined $val);
      }

      return $args;
   };

   method config_short_merge => sub {
      my ($self, $mod_list, $config_hash) = @_;

      $mod_list = [ $mod_list ] unless ref $mod_list;

      # figure out if the options are actually going to work
      foreach my $name (@$mod_list) {
         next if $name =~ /^\@/;

         my $class = _section_class($name);
         Class::Load::load_class($class);

         # handle mvp_aliases
         my %aliases = ();
         %aliases = %{$class->mvp_aliases} if $class->can('mvp_aliases');

         foreach my $k (keys %$config_hash) {
            warn $self->_fake_log_prefix." $name doesn't support argument '$k' as a standard attribute.  (Maybe you should use explicit arg passing?)\n"
               unless $class->can( $aliases{$k} || $k );
         }
      }

      return (
         { %$config_hash, %{$self->payload} },
         @$mod_list,
         $self->payload,
      );
   };

   # written entirely in hackish
   method _fake_log_prefix => sub {
      my $self = shift;
      my $plugin_name = _plugin_name(blessed $self);

      my @parts;
      push @parts, $self->name  if $self->name;
      push @parts, $plugin_name unless ($self->name =~ /\Q$plugin_name\E$/);

      '['.join('/', @parts).']';
   };
};

42;

__END__

=begin wikidoc

= SYNOPSIS

   # Yes, three lines of code works!
   package Dist::Zilla::PluginBundle::Foobar;
   Moose::with 'Dist::Zilla::Role::PluginBundle::Merged';
   sub configure { shift->add_merged( qw[ Plugin1 Plugin2 Plugin3 Plugin4 ] ); }

   # Or, as a more complex example...
   package Dist::Zilla::PluginBundle::Foobar;
   use Moose;

   with 'Dist::Zilla::Role::PluginBundle::Merged' => {
      mv_plugins => [ qw( Plugin1 =Dist::Zilla::Bizarro::Foobar Plugin2 ) ],
   };

   sub configure {
      my $self = shift;
      $self->add_merged(
         qw( Plugin1 @Bundle1 =Dist::Zilla::Bizarro::Foobar ),
         {},  # force no options on the following plugins
         qw( ArglessPlugin1 ArglessPlugin2 ),
         $self->config_rename(plugin_dupearg => 'dupearg', removearg => undef),
         qw( Plugin2 ),
         $self->config_short_merge(['Plugin3', 'Plugin4'], { defaultarg => 1 }),
      );
   }

= DESCRIPTION

This is a PluginBundle role, based partially on the underlying code from [Dist::Zilla::PluginBundle::Git].
As you can see from the example above, it's incredibly easy to make a bundle from this role.  It uses
[Dist::Zilla::Role::PluginBundle::Easy], so you have access to those same methods.

= METHODS

== add_merged

The {add_merged} method takes a list (not arrayref) of plugin names, bundle names (with the {@}
prefix), or full module names (with the {=} prefix).  This method combines {add_plugins} & {add_bundle},
and handles all of the payload merging for you.  For example, if your bundle is passed the following
options:

   [@Bundle]
   arg1 = blah
   arg2 = foobar

Then it will pass the {arg1/arg2} options to each of the plugins, *IF* they support the option.
Specifically, it does a {$class->can($arg)} check.  (Bundles are passed the entire payload set.)  If
{arg1} exists for multiple plugins, it will pass the same option to all of them.  If you need separate
options, you should consider using the {config_rename} method.

It will also accept hashrefs anywhere in the list, which will replace the payload arguments while
it processes.  This is useful for changing the options "on-the-fly" as plugins get processed.  The
replacement is done in order, and the changes will persist until it reaches the end of the list, or
receives another replacement.

If passed an arrayref, it will be directly passed to add_plugins.  Useful for plugins that use BUILDARGS
or some other non-standard configuration setup.

== config_rename

This method is sort of like the [config_slice|Dist::Zilla::Role::PluginBundle::Easy/config_slice] method,
but is more implicit than explicit.  It starts off with the entire payload (cloned), and renames any hash
pair that was passed:

   my $hash = $self->config_rename(foobar_arg1 => 'arg1');

This example will change the argument {foobar_arg1} to {arg1}.  This is handy if you want to make a
specific option for the plugin "Foobar" that doesn't clash with {arg1} on plugin "Baz":

   $self->add_merged(
      'Baz',
      $self->config_rename(foobar_arg1 => 'arg1', killme => ''),
      'Foobar',
   );

Any destination options are replaced.  Also, if the destination value is undef (or non-true), the key will
simply be deleted.  Keep in mind that this is all a clone of the payload, so extra calls to this method
will still start out with the original payload.

== config_short_merge

Like {config_rename}, this is meant to be used within an {add_merged} block.  It takes either a single
plugin (scalar) or multiple ones (arrayref) as the first parameter, and a hashref of argument/value pairs
as the second one.  This will merge in your own argument/value pairs to the existing payload, pass the
module list, and then pass the original payload back.  For example:

   $self->add_merged(
      $self->config_short_merge(['Baz', 'Foobar'], { arg1 => 1 }),  # these two plugins have payload + arg1
      'Boom',  # only has the original payload
   );

Furthermore, the argument hash is expanded prior to the payload, so they can be overwritten by the payload.
Think of this as default arguments to pass to the plugins.

= ROLE PARAMETERS

== mv_plugins

Certain configuration parameters are "multi-value" ones (or MVPs), and [Config::MVP] uses the
{mvp_multivalue_args} sub in each class to identify which ones exist.  Since you are trying to merge the
configuration parameters of multiple plugins, you'll need to make sure your new plugin bundle identifies those
same MVPs.

Because the INI reader is closer to the beginning of the DZ plugin process, it would be too late for
{add_merged} to start adding in keys to your {mvp_multivalue_args} array.  Thus, this role is parameterized
with this single parameter, and comes with its own {mvp_multivalue_args} method.  The syntax is a single
arrayref of strings in the same prefix structure as {add_merged}.  For example:

   with 'Dist::Zilla::Role::PluginBundle::Merged' => {
      mv_plugins => [ qw( Plugin1 Plugin2 ) ],
   };

The above will identify these two plugins has having MVPs.  When [Config::MVP] calls your {mvp_multivalue_args}
sub (which is built into this role), it will load these two plugin classes and populate the contents
of *their* {mvp_multivalue_args} sub as a combined list to pass over to [Config::MVP].  In other words,
as long as you identify all of the plugins that would have multiple values, your stuff "just works".

If you need to identify any extra parameters as MVPs (like your own custom MVPs or "dupe preventing" parameters
that happen to be MVPs), you should consider combining {mv_plugins} with an {after mvp_multivalue_args} sub.

= SUMMARY OF PARAMETERS

Here are all of the different options you can pass to {add_merged}:

   $self->add_merged(
      ### SCALARs ###
      # These are all passed to add_plugins with an implicit payload
      'Plugin',
      '@PluginBundle',
      '=Dist::Zilla::Bizarro::Plugin',  # explicit class of plugin

      ### ARRAYs ###
      # These are all passed to add_plugins with an explicit payload
      ['Plugin'],
      ['Plugin', 'NewName'],
      ['Plugin', \%new_payload ],
      ['Plugin', 'NewName', \%new_payload ],

      ### HASHs ###
      {},              # force no options until reset
      $self->payload,  # reset to original payload
      \%new_payload,   # only pass those arg/value pairs as the payload

      $self->config_slice(qw( arg1 arg2 )),                    # only pass those args -from- the payload
      $self->config_slice('arg1', { foobar_arg2 => 'arg2' }),  # only pass those args -from- the payload (with arg renaming)

      $self->config_rename(foobar_arg1 => 'arg1'),             # rename args in the payload (and pass everything else)
      $self->config_rename(killme => ''),                      # remove args in the payload (and pass everything else)

      ### Combinations ###
      $self->config_short_merge('Plugin', \%add_on_payload),   # add args to the payload, pass to Plugin, and reset to original
      $self->config_short_merge(
         [ qw( Plugin1 Plugin2 ) ],    # add args to the payload, pass to plugin list, and reset to original payload
         \%add_on_payload
      ),
   );

= CAVEATS

* Plugins that use non-standard payload methods will not be passed their options via {add_merged}, unless passed
an arrayref to {add_merged} with an specific payload.  The {config_merge} method will warn you of this, because
it knows that you really want to use that argument.  Others will not.

* Doing things more implicitly grants greater flexibility while sacrificing control.  YMMV.

=end wikidoc
