package Net::WAMP::SessionMessage;

use parent qw( Net::WAMP::Message );

#As of the 19 March 2017 draft, all session ID fields are the same.
use constant SESSION_SCOPE_ID_ELEMENT => 'Request';

1;
