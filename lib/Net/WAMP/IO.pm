package Net::WAMP::IO;

use strict;
use warnings;

use lib '/Users/Felipe/code/p5-Protocol-WAMP/lib';

use Protocol::WAMP::Messages ();

use Net::WAMP::X ();

use constant SUBPROTOCOL_BASE => 'wamp.2.';

sub new {
    my ($class, $in_fh, $out_fh) = @_;

    my $blocking_writes = $out_fh->blocking();
print "blocking? [$blocking_writes]\n";

    my $self = {
        _in_fh => $in_fh,
        _out_fh => $out_fh,
        _last_session_scope_id => 0,
        _write_queue => [],

        ( _write_func => $blocking_writes ? '_write_now' : '_enqueue_write' ),
    };

    return bless $self, $class;
}

sub write_wamp_message {
    my ($self, $wamp_msg) = @_;
#print "$self sending $wamp_msg\n";

    my $wamp_bytes = $self->_stringify( $wamp_msg->to_unblessed() );

#use Data::Dumper;
#print STDERR Dumper('WRITING', $wamp_bytes);

    my $write_func = $self->{'_write_func'};
print "WRITE via [$write_func]\n";

    $self->$write_func(
        $self->_serialized_wamp_to_transport_bytes($wamp_bytes),
    );

    return;
}

sub _write_now {
    my ($self) = shift;

    local $!;

    return syswrite( $self->{'_out_fh'}, $_[0] ) || do {
        die Net::WAMP::X->create('WriteError', OS_ERROR => $!) if $!;
    };
}

sub read_wamp_message {
    my ($self) = @_;
print STDERR "read_wamp\n";

    my $array_ref = $self->_destringify(

        #avoid creating the variable
        ($self->_read_transport_message() or return undef),
    );

    my $type_num = shift(@$array_ref);
    my $type = Protocol::WAMP::Messages::get_type($type_num);

    my $msg = $self->_create_msg( $type, @$array_ref );

    if ($msg->isa('Protocol::WAMP::SessionMessage')) {
print STDERR "$self GOT SESSION MESSAGE: $msg\n";
        my $ss_id = $msg->get( $msg->SESSION_SCOPE_ID_ELEMENT() );
print "ID: [$ss_id]\n";

        if ( $ss_id != 1 + $self->{'_last_session_scope_id'} ) {

            #TODO - Wampy.js is probably not the only client that screws this up.
            #die "Last-sent scope ID is “$self->{'_last_session_scope_id'}”; received “$ss_id”. (Should increment by 1!)";
        }

        $self->{'_last_session_scope_id'} = $ss_id;
    }

    return $msg;
}

sub messages_to_write {
    my ($self) = @_;

    return 0 + @{ $self->{'_write_queue'} };
}

sub process_write_queue {
    my ($self) = @_;

    while ( my $qi = $self->{'_write_queue'}[0] ) {
        my $written = $self->_write_now( $qi->[0] );

        if ($written == length $qi->[0]) {
print "SENT $written bytes\n";
            shift @{ $self->{'_write_queue'} };
            if ($qi->[1]) {
                $qi->[1]->();
            }
        }
        else {
            substr( $qi->[0], 0, length($written) ) = q<>;
            last;
        }
    }

    return;
}

sub get_next_session_scope_id {
    my ($self) = @_;

    return ++$self->{'_last_session_scope_id'};
}

#----------------------------------------------------------------------

#XXX De-duplicate TODO
sub _create_msg {
    my ($self, $name, @parts) = @_;

    my $mod = "Protocol::WAMP::Message::$name";
    Module::Load::load($mod) if !$mod->can('new');

    return $mod->new(@parts);
}

#----------------------------------------------------------------------

sub _enqueue_write {
    my $self = shift;

    push @{ $self->{'_write_queue'} }, \@_;

    return;
}

sub _set_serialization_format {
    my ($self, $serialization) = @_;

    my $ser_mod = "Protocol::WAMP::Serialization::$serialization";
    Module::Load::load($ser_mod) if !$ser_mod->can('stringify');
    $self->{'_serialization_module'} = $ser_mod;

    return $self;
}

sub _serialization_is_set {
    my ($self) = @_;

    return $self->{'_serialization_module'} ? 1 : 0;
}

sub _stringify {
    my ($self) = shift;
    return $self->{'_serialization_module'}->can('stringify')->(@_);
}

sub _destringify {
    my ($self) = shift;
#print STDERR Dumper('got', @_);
    return $self->{'_serialization_module'}->can('parse')->(@_);
}

1;
