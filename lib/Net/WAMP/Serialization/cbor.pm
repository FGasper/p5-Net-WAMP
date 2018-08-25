package Net::WAMP::Serialization::cbor;

use CBOR::XS ();

use constant {
    serialization => 'cbor',
    websocket_data_type => 'binary',
};

*stringify = *CBOR::XS::encode_cbor;
*parse = *CBOR::XS::decode_cbor;

1;
