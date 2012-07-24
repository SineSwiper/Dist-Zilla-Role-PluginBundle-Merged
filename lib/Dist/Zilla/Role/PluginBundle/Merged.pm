package Dist::Zilla::Role::PluginBundle::Merged;

our $VERSION = '0.90'; # VERSION
# ABSTRACT: Mindnumbingly easy way to create a PluginBundle

use sanity;
use Moose::Role;
use Class::MOP;
use Storable 'dclone';

use String::RewritePrefix 0.005 rewrite => {
   -as => '_section_class',
   prefixes => {
      ''  => 'Dist::Zilla::Plugin::',
      '@' => 'Dist::Zilla::PluginBundle::',
      '=' => ''
   },
};

with 'Dist::Zilla::Role::PluginBundle::Easy';

has mvp_multivalue_args => (
  is       => 'ro',
  isa      => ArrayRef,
  default  => sub { [] },
);

sub add_merged {
   my $self = shift;
   my @list = @_;
   my $arg = $self->payload;

   my %multi;
   my @config;
   foreach my $name (@list) {
      if (ref $name) {
         $arg = $name;
         next;
      }
   
      my $class = _section_class($name);
      Class::MOP::load_class($class);
      @multi{$class->mvp_multivalue_args} = ();

      if ($name =~ /^\@/) {
         # just give it everything, since we can't separate them out
         $self->add_bundle($name => $arg);
      }
      else {
         my %payload;
         foreach my $k (keys %$arg) {
            $payload{$k} = $arg->{$k} if $class->does($k);
         }
         $self->add_plugins([ "=$class" => $name => \%payload ]);
      }
   }
 
   push @{$self->mvp_multivalue_args}, keys %multi;
}

sub config_rename {
   my $self     = shift;
   my $payload  = $self->payload
   my $args     = dclone($payload);
   my $chg_list = ref $_[0] ? $_[0] : { @_ };
   
   foreach my $key (keys $chg_list) {
      my $new_key = $chg_list->{$key};
      my $val     = delete $args->{$key};
      next unless ($new_key);
      $args->{$new_key} = $val if (defined $val);
   }
   
   return $args;
}

42;



=pod

=encoding utf-8

=head1 NAME

Dist::Zilla::Role::PluginBundle::Merged - Mindnumbingly easy way to create a PluginBundle

=head1 SYNOPSIS

    ; Yes, three lines of code works!
    package Dist::Zilla::PluginBundle::Foobar;
    Moose::with 'Dist::Zilla::Role::PluginBundle::Merged';
    sub configure { shift->add_merged( qw[ Plugin1 Plugin2 Plugin3 Plugin4 ] ); }
 
    ; Or, as a more complex example...
    sub configure {
       my $self = shift;
       shift->add_merged(
          qw( Plugin1 @Bundle1 =Dist::Zilla::Bizarro::Foobar ),
          {},  # force no options on the following plugins
          qw( ArglessPlugin1 ArglessPlugin2 ),
          $self->config_rename(plugin_dupearg => 'dupearg', removearg => undef),
          qw( Plugin2 ),
       );
    }

=head1 DESCRIPTION

This is a PluginBundle role, based partially on a code example from L<Dist::Zilla::PluginBundle::Git>.
As you can see from the example above, it's incredibly easy to make a bundle from this role.  It uses
L<Dist::Zilla::Role::PluginBundle::Easy>, so you have access to those same methods.

=head1 METHODS

=head2 add_merged

The C<<< add_merged >>> method takes a list (not arrayref) of plugin names, bundle names (with the C<<< @ >>>
prefix), or full module names (with the C<<< = >>> prefix).  This method combines C<<< add_plugins >>> & C<<< add_bundle >>>,
and handles all of the payload merging for you.  For example, if your bundle is passed the following
options:

    [@Bundle]
    arg1 = blah
    arg2 = foobar

Then it will pass the C<<< arg1 >>>E<sol>{arg2} options to each of the plugins, B<IF> they support the option.  
Specifically, it does a C<<< $class->does($arg) >>> check.  (Bundles are passed the entire payload set.)  If
C<<< arg1 >>> exists for multiple plugins, it will pass the same option to all of them.  If you need separate
options, you should consider using the C<<< config_rename >>> method.

It will also accept hashrefs anywhere in the list, which will replace the payload arguments while
it processes.  This is useful for changing the options "on-the-fly" as plugins get processed.  The 
replacement is done in order, and the changes will persist until it reaches the end of the list, or
receives another replacement.

=head2 config_rename

This method is sort of like the C<<< [Dist::Zilla::Role::PluginBundle::Easy/config_slice|config_slice] >>> method,
but is more implicit than explicit.  It starts off with the entire payload (cloned), and renames any hash
pair that was passed:

    my $hash = $self->config_rename(foobar_arg1 => 'arg1');

This example will change the argument C<<< foobar_arg1 >>> to C<<< arg1 >>>.  This is handy if you want to make a
specific option for the plugin "Foobar" that doesn't clash with C<<< arg1 >>> on plugin "Baz":

    $self->add_merged(
       'Baz',
       $self->config_rename(foobar_arg1 => 'arg1'),
       'Foobar',
    );

Any destination options are replaced.  Also, if the hash value is undef (or non-true), the key will
simply be deleted.  Keep in mind that this is all a clone of the payload, so extra calls to this method
will still start out with the original payload.

=head1 AVAILABILITY

The project homepage is L<https://github.com/SineSwiper/Dist-Zilla-Role-PluginBundle-Merged/wiki>.

The latest version of this module is available from the Comprehensive Perl
Archive Network (CPAN). Visit L<http://www.perl.com/CPAN/> to find a CPAN
site near you, or see L<https://metacpan.org/module/Dist::Zilla::Role::PluginBundle::Merged/>.

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Internet Relay Chat

You can get live help by using IRC ( Internet Relay Chat ). If you don't know what IRC is,
please read this excellent guide: L<http://en.wikipedia.org/wiki/Internet_Relay_Chat>. Please
be courteous and patient when talking to us, as we might be busy or sleeping! You can join
those networks/channels and get help:

=over 4

=item *

irc.perl.org

You can connect to the server at 'irc.perl.org' and join this channel: #distzilla then talk to this person for help: SineSwiper.

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests via L<L<https://github.com/SineSwiper/Dist-Zilla-Role-PluginBundle-Merged/issues>|GitHub>.

=head1 AUTHOR

Brendan Byrd <BBYRD@CPAN.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2012 by Brendan Byrd.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut


__END__

