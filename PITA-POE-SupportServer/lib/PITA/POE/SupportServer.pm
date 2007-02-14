package PITA::POE::SupportServer;

use strict;
use warnings;
use Params::Util qw( _ARRAY _HASH );

use POE qw(Filter::Line Wheel::Run );
use POE::Component::Server::SimpleContent;
use POE::Component::Server::SimpleHTTP;
use URI;
use MIME::Types qw(by_suffix);

use Process;
use base qw( Process );

our $VERSION = '0.01';

sub new {
    my $package = shift;

    # TODO error checking here?

    bless { params => { @_ } }, $package;
}

sub prepare {
    my $self = shift;
    my %opt =  %{ delete $self->{params} };

    $opt{lc $_} = delete $opt{$_} for keys %opt;

    unless ( _ARRAY($opt{execute}) ) {
        $self->{errstr} = 'execute must be an array ref';
        return undef;
    }
    $self->{execute}               = delete $opt{execute};
    
    unless ( _HASH($opt{http_mirrors}) ) {
        $self->{errstr} = 'http_mirrors must be a hash ref of image paths to local paths';
        return;
    }
    $self->{http_mirrors}          = delete $opt{http_mirrors};
    $self->{http_local_addr}       = delete $opt{http_local_addr} || '127.0.0.1';
    $self->{http_local_port}       = delete $opt{http_local_port} || 80;
    $self->{http_result}           = delete $opt{http_result} || [ '/result.xml' ];
    unless ( _ARRAY( $self->{http_result} ) ) {
        $self->{http_result} = [ $self->{http_result} ];
    }
    $self->{http_startup_timeout}  = delete $opt{http_startup_timeout} || 30;
    $self->{http_activity_timeout} = delete $opt{http_activity_timeout} || 3600;
    $self->{http_shutdown_timeout} = delete $opt{http_shutdown_timeout} || 10;

    if ( keys %opt ) {
        $self->{errstr} = 'unknown parameters: '.join( ',', keys %opt );
        return;
    }

    $self->{_prepared} = 1;
    $self->{_has_run} = 0;
 
    1;
}

sub run {
    my $self = shift;

    # TODO setup timers
    
    unless( $self->{_prepared} ) {
        $self->{errstr} = "You must prepare() before run()";
        return;
    }
    
    $self->{_has_run}++;

    $self->{_session_id} = POE::Session->create(
        object_states => [
            $self => [qw(
                _start
                _signals
                _http_success
                _http_result
                execute
                shutdown
                
                _error
                _closed
                _stdin
                _stderr
                _stdout

                _startup_timeout
                _activity_timeout
                _shutdown_timeout
            )],
        ]
    )->ID();

    $poe_kernel->run();

    $self->{errstr} ? undef : 1;
}

sub http_result {
    shift->{_http_result} || return;
}

sub has_run {
    shift->{_has_run} || 0;
}

# Private methods and events

sub _start {
    my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];
    $self->{_session_id} = $session->ID();

    #$kernel->sig( DIE => '_signals' );

    $self->{content_servers} = [ ];

    my $handlers = [ ];

    while ( my ($alias_path,$root_dir) = each %{ $self->{http_mirrors} } ) {
	my $content = POE::Component::Server::SimpleContent->spawn( 
		root_dir => $root_dir,
		alias_path => $alias_path,
	);
	next unless $content;
	push @{ $self->{content_servers} }, $content;
	push @{ $handlers }, { DIR     => "^$alias_path",
			       SESSION => $content->session_id(),
			       EVENT   => 'request', };
    }

    foreach my $result ( @{ $self->{http_result} } ) {
	push @{ $handlers }, { DIR     => "^$result\$",
			       SESSION => $self->{_session_id},
			       EVENT   => '_http_result', };
    }

    push @{ $handlers }, { DIR     => '^/$', 
			   SESSION => $self->{_session_id},
			   EVENT   => '_http_success', };

    $self->{_http_server} = POE::Component::Server::SimpleHTTP->new(
	ALIAS    => __PACKAGE__ . $$,
	ADDRESS  => $self->{http_local_addr},
	PORT     => $self->{http_local_port},
	HANDLERS => $handlers,
    );

    $kernel->yield('execute');

    return;
}

sub _signals {
    my $sig = $_[ ARG0 ];

    if ( $sig eq 'DIE' ) {
        my ( $kernel, $self, $event, $file, $line, $from_state, $error )
            = @_[ KERNEL, OBJECT, ARG2 .. ARG6 ];
    
        $self->{errstr} = "POE Exception at line $line in file $file "
            ." (state '$from_state' called '$event') Error: $error";

        $kernel->sig_handled();

        $kernel->call( $_[ SESSION ] => 'shutdown' );
    }
}

sub _http_success {
  my ($kernel,$self,$sender,$request,$response) = @_[KERNEL,OBJECT,SENDER,ARG0,ARG1];
  $kernel->alarm_remove( delete $self->{_http_startup_timer} );
  $response->code( 200 );
  $response->content( 'OK' );
  $response->content_type( 'text/html' );
  $kernel->call( $sender, 'DONE', $response );
  return;
}

sub _http_result {
  my ($kernel,$self,$sender,$request,$response) = @_[KERNEL,OBJECT,SENDER,ARG0,ARG1];
  my $uri = URI->new( $request->uri );
  my $path = $uri->path;
  if ( $request->method() eq 'PUT' ) {
	if ( grep { $_ eq $path } @{ $self->{http_result} } ) {
	}
	else {
	   $response->code( 405 );
	   $response->content_type( 'text/html' );
	   $response->content('NOK');
	}
  }
  else {
	if ( defined $self->{_http_result}->{ $path } ) {
	   my ($mediatype, $encoding) = by_suffix( $path );
	   $response->code( 200 );
	   $response->content_type( $mediatype || 'text/html' );
	   $response->content( $self->{_http_result}->{ $path } );
	}
	else {
	   $response = generate_404( $response );
	}
  }
  $kernel->call( $sender, 'DONE', $response );
  return;
}

sub execute {
    my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];

    my @args = @{$self->{execute}};
   
    $self->{_http_startup_timer} = $kernel->alarm_set( _startup_timeout => $self->{http_startup_timeout} );
 #   $self->{_http_activity_timer} = $kernel->alarm_set( activity_timeout => $self->{http_activity_timeout} );
   
    $self->{_wheel} = POE::Wheel::Run->new(
        Program      => shift @args,
        ProgramArgs  => \@args,
        StderrFilter => POE::Filter::Line->new(),
        StdioFilter  => POE::Filter::Line->new(),
        ErrorEvent   => '_error',
        CloseEvent   => '_closed',
        StdinEvent   => '_stdin',
        StdoutEvent  => '_stdout',
        StderrEvent  => '_stderr',
    );
}

sub shutdown {
    my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];
    
    # XXX is this right?
    $self->{_http_shutdown_timer} = $kernel->alarm_set( shutdown_timeout => $self->{http_shutdown_timeout} );
    
    $self->{_wheel}->kill() if ( $self->{_wheel} );

    # TODO set timer and recheck for wheel closure
    
    delete @{$self}->{qw( _http_service _http_server )};
}

sub _error {
    my ( $kernel, $self, $ret, $errno, $error, $wheel_id, $handle ) = @_[ KERNEL, OBJECT, ARG0 .. ARG5 ];
    
    $self->{errstr} = "Error no $errno on $handle : $error ( Return value: $ret )";

    $kernel->call( $_[ SESSION ] => 'shutdown' );
}

sub _closed {
    my ( $self, $kernel ) = @_[ OBJECT, KERNEL];
    
    $self->{_wheel_closed}++;
    
    $kernel->call( $_[ SESSION ] => 'shutdown' );
}

sub _stdin {
    warn $_[ARG0];
}

sub _stdout {
    warn $_[ARG0];
}

sub _stderr {
    warn $_[ARG0];
}

sub _startup_timeout {
    warn "startup_timeout";
}

sub _activity_timeout {
    warn "activity_timeout";
}

sub _shutdown_timeout {
    warn "shutdown_timeout";
}

1;

__END__

=head1 NAME

PITA::POE::SupportServer

=head1 SYNOPSIS

  use PITA::POE::SupportServer;

  my $server = PITA::POE::SupportServer->new(
          execute => [
                  '/usr/bin/qemu',
                  '-snapshot',
                  '-hda',
                  '/var/pita/image/ba312bb13f.img',
                  ],
          http_local_addr => '127.0.0.1',
          http_local_port => 80,
          http_mirrors => {
                  '/cpan' => '/var/cache/minicpan',
                  },
          http_result => '/result.xml',
          http_startup_timeout => 30,
          http_activity_timeout => 3600,
          http_shutdown_timeout => 10,
          ) or die "Failed to create support server";
  
  $server->prepare
          or die "Failed to prepare support server";
  
  $server->run
          or die "Failed to run support server";
  
  my $result_file = $server->http_result('/result.xml')
          or die "Guest Image execution failed";

=head1 ABSTRACT

=head1 DESCRIPTION

=head1 METHODS

=head2 EXPORT

Nothing.

=head1 AUTHORS

David Davis E<lt>xantus@cpan.orgE<gt>, Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 SEE ALSO

L<PITA>, L<POE>, L<Process>, L<http://ali.as/>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 David Davis. All rights reserved.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut

