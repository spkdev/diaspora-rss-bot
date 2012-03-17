require 5.004;
use ExtUtils::MakeMaker;

WriteMakefile(
              'NAME'         => 'Diaspora::Client',
              'VERSION_FROM' => 'lib/Diaspora/Client.pm',
              'PREREQ_PM'    => {
				 'File::Pid' => 0,
				 'XML::FeedPP' => 0,
				 'Getopt::Long' => 0,
				 'Config::Tiny' => 0,
				 'Digest::MD5' => 0,
				 'DBI' => 0,
				 'DBD::SQLite' => 0,
				 'JSON' => 0,
				 'LWP::UserAgent' => 0,
				 'HTML::Entities' => 0,
				 'URI::Escape' => 0,
				 'HTML::WikiConverter' => 0,
				 'HTML::WikiConverter::Diaspora' => 0
                                },
	      'EXE_FILES'    => [ 'script/diaspora-rss' ],
	      ($ExtUtils::MakeMaker::VERSION ge '6.31'? ('LICENSE'              => 'perl', ) : ()),
              'AUTHOR'       => 'Oliver',
              'clean'        => {
                                 FILES => 't/*.out *~ */*~ */*/*~ */*/*/*~'
                                },

)

