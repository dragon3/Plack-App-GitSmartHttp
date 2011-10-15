package Plack::App::GitSmartHttp;

use strict;
use warnings;

use parent qw/Plack::Component/;
use Plack::Request;
use Plack::Util;
use Plack::Util::Accessor qw( root git_path upload_pack received_pack );
use HTTP::Date;
use Cwd ();
use File::Spec::Functions;
use File::chdir;
use IPC::Open3;

our $VERSION = '0.01';

my @SERVICES = (
    [ 'POST', 'service_rpc', qr{(.*?)/git-upload-pack$},  'upload-pack' ],
    [ 'POST', 'service_rpc', qr{(.*?)/git-receive-pack$}, 'receive-pack' ],

    [ 'GET', 'get_info_refs',    qr{(.*?)/info/refs$} ],
    [ 'GET', 'get_text_file',    qr{(.*?)/HEAD$} ],
    [ 'GET', 'get_text_file',    qr{(.*?)/objects/info/alternates$} ],
    [ 'GET', 'get_text_file',    qr{(.*?)/objects/info/http-alternates$} ],
    [ 'GET', 'get_info_packs',   qr{(.*?)/objects/info/packs$} ],
    [ 'GET', 'get_text_file',    qr{(.*?)/objects/info/[^/]*$} ],
    [ 'GET', 'get_loose_object', qr{(.*?)/objects/[0-9a-f]{2}/[0-9a-f]{38}$} ],
    [
        'GET', 'get_pack_file', qr{(.*?)/objects/pack/pack-[0-9a-f]{40}\.pack$}
    ],
    [ 'GET', 'get_idx_file', qr{(.*?)/objects/pack/pack-[0-9a-f]{40}\.idx$} ],
);

sub call {
    my $self = shift;
    my $env  = shift;
    my $req  = Plack::Request->new($env);

    my ( $cmd, $path, $reqfile, $rpc ) = $self->match_routing($req);

    return $self->return_404 unless $cmd;
    return $self->return_405 if $cmd eq 'not_allowed';

    my $dir = $self->get_git_repo_dir($path);
    return $self->return_404 unless $dir;

    {
        local $CWD = $dir;
        $self->$cmd(
            {
                req     => $req,
                path    => $path,
                reqfile => $reqfile,
                rpc     => $rpc
            }
        );
    }
}

sub get_service {
    my $self = shift;
    my $req  = shift;

    my $service = $req->param('service');
    return unless $service;
    return unless substr( $service, 0, 4 ) eq 'git-';
    $service =~ s/git-//g;
    return $service;
}

sub match_routing {
    my $self = shift;
    my $req  = shift;

    my ( $cmd, $path, $file, $rpc );
    for my $s (@SERVICES) {
        my $match = $s->[2];
        if ( $req->path_info =~ /$match/ ) {
            return ('not_allowed') if $s->[0] ne uc( $req->method );
            $cmd  = $s->[1];
            $path = $1;
            $file = $req->path_info;
            $file =~ s|\Q$path/\E||;
            $rpc = $s->[3];
            return ( $cmd, $path, $file, $rpc );
        }
    }
    return ();
}

sub get_git_repo_dir {
    my $self = shift;
    my $path = shift;

    my $root = $self->root || `pwd`;
    chomp $root;
    $path = catdir( $root, $path );
    return $path if ( -d $path );
    return;
}

# TODO
sub service_rpc {
    my $self = shift;
    my $args = shift;

    my $req = $args->{req};
    my $rpc = $args->{rpc};

    return $self->return_403
      unless $self->has_access( $req, $rpc, 1 );

    my $res = $req->new_response(200);
    $res->headers(
        [ 'Content-Type' => sprintf( 'application/x-git-%s-result', $rpc ), ] );

    my @cmd = $self->git_command( $rpc, '--stateless-rpc', '.' );

    my $pid = open3( my $cin, my $cout, undef, @cmd );
    print $cin $req->content;
    close $cin;
    my $out;
    while (<$cout>) {
        $out .= $_;
    }
    close $cout;
    waitpid( $pid, 0 );
    $res->body($out);
    $res->finalize;
}

sub get_info_refs {
    my $self = shift;
    my $args = shift;

    my $req     = $args->{req};
    my $service = $self->get_service($req);
    if ( $self->has_access( $args->{req}, $service ) ) {
        my @cmd =
          $self->git_command( $service, '--stateless-rpc', '--advertise-refs',
            '.' );

        my $pid = open3( my $cin, my $cout, undef, @cmd );
        close $cin;
        my $refs;
        while (<$cout>) {
            $refs .= $_;
        }
        close $cout;
        waitpid( $pid, 0 );

        my $res = $req->new_response(200);
        $res->headers(
            [
                'Content-Type' =>
                  sprintf( 'application/x-git-%s-advertisement', $service ),
            ]
        );
        my $body =
          pkt_write("# service=git-${service}\n") . pkt_flush() . $refs;
        $res->body($body);
        return $res->finalize;
    }
    else {
        return $self->dumb_info_refs($args);
    }
}

sub dumb_info_refs {
    my $self = shift;
    my $args = shift;

    $self->update_server_info;
    $self->send_file( $args, "text/plain; charset=utf-8" );
}

sub get_info_packs {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "text/plain; charset=utf-8" );
}

sub get_loose_object {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "application/x-git-loose-object" );
}

sub get_pack_file {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "application/x-git-packed-objects" );
}

sub get_idx_file {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "application/x-git-packed-objects-toc" );
}

sub get_text_file {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "text/plain" );
}

sub update_server_info {
    my $self = shift;
    system( $self->git_command('update-server-info') );
}

sub git_command {
    my $self     = shift;
    my @commands = @_;
    my $git_bin  = $self->git_path || 'git';
    return ( $git_bin, @commands );
}

sub has_access {
    my $self = shift;
    my ( $req, $rpc, $check_content_type ) = @_;

    if (   $check_content_type
        && $req->content_type ne sprintf( "application/x-git-%s-request", $rpc )
      )
    {
        return;
    }
    if ( !$rpc || ( $rpc ne 'upload-pack' && $rpc ne 'receive-pack' ) ) {
        return;
    }
    if ( $rpc eq 'receive-pack' ) {
        return $self->received_pack;
    }
    elsif ( $rpc eq 'upload-pack' ) {
        return $self->upload_pack;
    }
    return $self->get_config_setting($rpc);
}

sub get_config_setting {
    my $self = shift;
    my $rpc  = shift;

    $rpc =~ s/-//g;
    my $setting = $self->get_git_config("http.$rpc");
    if ( $rpc eq 'uploadpack' ) {
        return $setting ne 'false';
    }
    else {
        return $setting eq 'true';
    }
}

sub get_git_config {
    my $self        = shift;
    my $config_name = shift;

    my @cmd = $self->git_command( 'config', '$config_name' );
    my $pid = open3( my $cin, my $cout, undef, @cmd );
    close $cin;
    my $config;
    while (<$cout>) {
        $config .= $_;
    }
    close $cout;
    waitpid( $pid, 0 );
    chomp $config;
    return $config;
}

sub send_file {
    my $self = shift;
    my ( $args, $content_type ) = @_;

    my $file = $args->{reqfile};
    return $self->return_404 unless -e $file;

    my @stat = stat $file;
    my $res  = $args->{req}->new_response(200);
    $res->headers(
        [
            'Content-Type'  => $content_type,
            'Last-Modified' => HTTP::Date::time2str( $stat[9] ),
            'Expires'       => 'Fri, 01 Jan 1980 00:00:00 GMT',
            'Pragma'        => 'no-cache',
            'Cache-Control' => 'no-cache, max-age=0, must-revalidate',
        ]
    );

    if ( $stat[7] ) {
        $res->header( 'Content-Length' => $stat[7] );
    }
    open my $fh, "<:raw", $file
      or return $self->return_403;

    Plack::Util::set_io_path( $fh, Cwd::realpath($file) );
    $res->body($fh);
    $res->finalize;
}

sub pkt_flush {
    return '0000';
}

sub pkt_write {
    my $str = shift;
    return sprintf( '%04x', length($str) + 4 ) . $str;
}

sub return_405 {
    my $self = shift;
    return [
        405, [ 'Content-Type' => 'text/plain', 'Content-Length' => 18 ],
        ['Method Not Allowed']
    ];
}

sub return_403 {
    my $self = shift;
    return [
        403, [ 'Content-Type' => 'text/plain', 'Content-Length' => 9 ],
        ['Forbidden']
    ];
}

sub return_400 {
    my $self = shift;
    return [
        400, [ 'Content-Type' => 'text/plain', 'Content-Length' => 11 ],
        ['Bad Request']
    ];
}

sub return_404 {
    my $self = shift;
    return [
        404, [ 'Content-Type' => 'text/plain', 'Content-Length' => 9 ],
        ['Not Found']
    ];
}

1;
__END__

=head1 NAME

  Plack::App::GitSmartHttp

=head1 SYNOPSIS

  use Plack::App::GitSmartHttp;

=head1 DESCRIPTION

  Plack::App::GitSmartHttp is Git Smart HTTP Server Plack Implementation.

=head1 WARNING

  This software is under the heavy development and considered ALPHA quality.

=head1 AUTHOR

  Ryuzo Yamamoto E<lt>ryuzo.yamamoto@gmail.comE<gt>

=head1 SEE ALSO

  Smart HTTP Transport : <http://progit.org/2010/03/04/smart-http.html>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
