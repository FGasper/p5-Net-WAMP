package Net::WAMP::Base::TowardCallee;

use strict;
use warnings;

sub caller_can_receive_progress {
    return Types::Serialiser::is_true( $_[0]->get('Metadata')->{'receive_progress'} );
}

1;
