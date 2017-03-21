package Net::WAMP::IO;

use strict;
use warnings;

use lib '/Users/Felipe/code/p5-Protocol-WAMP/lib';

use Protocol::WAMP::Messages ();

use constant SUBPROTOCOL_BASE => 'wamp.2.';

sub new {
    my ($class) = @_;

    return bless { _last_session_scope_id => 0 }, $class;
}

sub write_wamp_message {
    my ($self, $wamp_msg) = @_;
print "$self sending $wamp_msg\n";

    my $wamp_bytes = $self->_stringify( $wamp_msg->to_unblessed() );

use Data::Dumper;
print STDERR Dumper('WRITING', $wamp_bytes);

    syswrite( $self->{'_out_fh'}, $self->_serialized_wamp_to_transport_bytes($wamp_bytes) );

    return;
}

sub read_wamp_message {
    my ($self) = @_;

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

        if ( $ss_id == 1 + $self->{'_last_session_scope_id'} ) {

            #increment by one
            $self->get_next_session_scope_id();
        }
        else {
            die "Last-sent scope ID is “$self->{'_last_session_scope_id'}”; received “$ss_id”. (Should increment by 1!)";
        }
    }

    return $msg;
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

sub _set_serialization_format {
    my ($self, $serialization) = @_;

    my $ser_mod = "Protocol::WAMP::Serialization::$serialization";
    Module::Load::load($ser_mod) if !$ser_mod->can('stringify');
    $self->{'_serialization_module'} = $ser_mod;

    return $self;
}

sub _get_serialization_format {
    return shift()->{'_serialization_module'}->serialization();
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
