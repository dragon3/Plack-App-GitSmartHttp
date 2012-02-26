use strict;
use Test::More;

use Plack::Test;
use HTTP::Request::Common;

BEGIN { use_ok 'Plack::App::GitSmartHttp' }

my $app = Plack::App::GitSmartHttp->new(
    root          => "t/test_repos",
    upload_pack   => 0,
    received_pack => 1,
);

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( POST "/repo1/git-upload-pack" );
    is $res->code, 403;
};

done_testing
