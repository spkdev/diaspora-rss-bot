require 5.004;
use ExtUtils::MakeMaker;

WriteMakefile(
              'NAME'         => 'HTML::WikiConverter::Diaspora',
              'VERSION_FROM' => 'lib/HTML/WikiConverter/Diaspora.pm',
              'PREREQ_PM'    => {
				 'HTML::WikiConverter' => 0,
                                },
	      ($ExtUtils::MakeMaker::VERSION ge '6.31'? ('LICENSE'              => 'perl', ) : ()),
              'AUTHOR'       => 'Oliver',
              'clean'        => {
                                 FILES => 't/*.out *~ */*~ */*/*~ */*/*/*~'
                                },

);
 
