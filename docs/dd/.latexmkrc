$pdf_mode = 1;
$out_dir = '../out/dd';
# The document's own folder first, then docs/ for the class.
$ENV{'TEXINPUTS'} = '.:..:' . ($ENV{'TEXINPUTS'} // '');
