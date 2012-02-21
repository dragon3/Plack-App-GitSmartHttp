use strict;
use Test::More;

use Plack::Test;
use HTTP::Request::Common;

BEGIN { use_ok 'Plack::App::GitSmartHttp' }

my $app = Plack::App::GitSmartHttp->new(
    root          => "t/test_repos",
    upload_pack   => 1,
    received_pack => 1,
);

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/repo1/git-upload-pack" );
    is $res->code, 405;
};

test_psgi $app, sub {
    my $cb = shift;
    my $req = HTTP::Request->new( GET => "/repo1/git-upload-pack" );
    $req->protocol("HTTP/1.0");
    my $res = $cb->($req);
    is $res->code, 400;
};

done_testing
