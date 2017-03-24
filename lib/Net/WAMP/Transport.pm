package Net::WAMP::Transport;

use strict;
use warnings;

use Net::WAMP::Messages ();

use IO::Sys ();

use Net::WAMP::X ();

use constant CONSTRUCTOR_OPTS => ();

sub new {
    my ($class, $in_fh, $out_fh, %opts) = @_;

    my $blocking_writes = $out_fh->blocking();

    my $self = {
        _in_fh => $in_fh,
        _out_fh => $out_fh,
        _last_session_scope_id => 0,
        _write_queue => [],
        _read_buffer => q<>,

        ( map { ( "_$_" => $opts{$_} ) } $class->CONSTRUCTOR_OPTS() ),

        _write_func => ( $blocking_writes ? '_write_now_then_callback' : '_enqueue_write' ),
    };

    return bless $self, $class;
}

sub write_wamp_message {
    my ($self, $wamp_msg) = @_;

    $self->_verify_not_shut_down();

    my $wamp_bytes = $self->_stringify( $wamp_msg->to_unblessed() );

    $self->_write_bytes(
        $self->_serialized_wamp_to_transport_bytes($wamp_bytes),
    );

    return;
}

sub read_wamp_message {
    my ($self) = @_;

    $self->_verify_not_shut_down();

    my $array_ref = $self->_destringify(

        #avoid creating the variable
        ($self->_read_transport_message() or return undef),
    );

    my $type_num = shift(@$array_ref);
    my $type = Net::WAMP::Messages::get_type($type_num);

    my $msg = $self->_create_msg( $type, @$array_ref );

    if ($msg->isa('Net::WAMP::SessionMessage')) {
        my $ss_id = $msg->get( $msg->SESSION_SCOPE_ID_ELEMENT() );

        if ( $ss_id != 1 + $self->{'_last_session_scope_id'} ) {

            #XXX TODO - Wampy.js is probably not the only client that screws this up.
            #die "Last-sent scope ID is “$self->{'_last_session_scope_id'}”; received “$ss_id”. (Should increment by 1!)";
        }

        $self->{'_last_session_scope_id'} = $ss_id;
    }

    return $msg;
}

sub get_write_queue_size {
    my ($self) = @_;

    return 0 + @{ $self->{'_write_queue'} };
}

sub shift_write_queue {
    my ($self) = @_;

    return shift @{ $self->{'_write_queue'} };
}

sub process_write_queue {
    my ($self) = @_;

    local $SIG{'PIPE'} = 'IGNORE' if $self->_is_shut_down();

    while ( my $qi = $self->{'_write_queue'}[0] ) {
        if ( $self->_write_now_then_callback( @$qi ) ) {
            shift @{ $self->{'_write_queue'} };
        }
        else {
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

    my $mod = "Net::WAMP::Message::$name";
    Module::Load::load($mod) if !$mod->can('new');

    return $mod->new(@parts);
}

#----------------------------------------------------------------------

sub _write_bytes {
    my $self = shift;

    my $write_func = $self->{'_write_func'};

    return $self->$write_func(@_);
}

sub _write_now_then_callback {
    my ($self) = shift;

    local $!;

    my $wrote = IO::Sys::write( $self->{'_out_fh'}, $_[0] ) || do {
        die Net::WAMP::X->create('WriteError', OS_ERROR => $!) if $!;
        return undef;
    };

    if ($wrote == length $_[0]) {
        $self->{'_write_queue_partial'} = 0;
        $_[1]->() if $_[1];
        return 1;
    }

    substr( $_[0], 0, $wrote ) = q<>;

    #This seems useful to track … ??
    $self->{'_write_queue_partial'} = 1;

    return 0;
}

#We assume here that whatever read may be incomplete at first
#will eventually be repeated so that we can complete it. e.g.:
#
#   - read 4 bytes, receive 1, cache it - return q<>
#   - select()
#   - read 4 bytes again; since we already have 1 byte, only read 3
#       … and now we get the remaining 3, so return the buffer.
#
sub _read_now {
    my ($self, $bytes) = @_;

    local $!;

    $bytes -= IO::Sys::read( $self->{'_in_fh'}, $self->{'_read_buffer'}, $bytes - length $self->{'_read_buffer'}, length $self->{'_read_buffer'} ) || do {
        die Net::WAMP::X->create('ReadError', OS_ERROR => $!) if $!;

        die Net::WAMP::X->create('EmptyRead') if !$self->{'_in_fh'}->blocking();
    };

    return $bytes ? q<> : substr( $self->{'_read_buffer'}, 0, length $self->{'_read_buffer'}, q<> );
}

sub _read_buffer_sr {
    my ($self) = @_;
    return \$self->{'_read_buffer'};
}

sub _enqueue_write {
    my $self = shift;

    push @{ $self->{'_write_queue'} }, \@_;

    return;
}

sub _set_serialization_format {
    my ($self, $serialization) = @_;

    my $ser_mod = "Net::WAMP::Serialization::$serialization";
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
    return $self->{'_serialization_module'}->can('parse')->(@_);
}

sub _set_shutdown {
    shift()->{'_shutdown_happened'} = 1;
    return;
}

sub _is_shut_down {
    my ($self) = @_;

    return $self->{'_shutdown_happened'} ? 1 : 0;
}

sub _verify_not_shut_down {
    my ($self) = @_;

    if ($self->{'_shutdown_happened'}) {
        die "$self is already shut down!";
    }

    return;
}

1;
