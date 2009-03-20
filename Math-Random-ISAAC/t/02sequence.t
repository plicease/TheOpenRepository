#!/usr/bin/perl -T

# t/02sequence.t
#  Checks that the generated sequence matches the reference
#
# By Jonathan Yu <frequency@cpan.org>, 2009. All rights reversed.
#
# $Id$
#
# This package and its contents are released by the author into the
# Public Domain, to the full extent permissible by law. For additional
# information, please see the included `LICENSE' file.

use strict;
use warnings;

use Test::More;

# Test the Pure Perl version only; the XS version has its own tests
use Math::Random::ISAAC::PP ();

my @results = (
   405143795,  806046349,  807101986, 2961886497,  695195257,
  2572289769, 3019876533,  264870948, 1594302383, 1378164207,
  2303672770, 3427572475, 2529378164,  880588573, 3373240253,
  2790847866, 3317866008, 1649015337, 3135336442,  633893309,
  4106706468, 1521740473, 2890206095,  371838884,    1501295,
  4068232461, 1734642455,   96489422, 1154744185, 3333214735,
  1194318228, 2216767940, 3939805440, 3223247373, 2657111163,
  4220128921,   48331631, 3904173607, 3338935982, 1121033431,
  2740513684,  432677208, 1810288257, 1267770590,  653293389,
  1317245706,  613602422, 3112172222, 1734133934, 1291702868,
  1564213482, 2075811501, 1866864656, 3203809002, 1928033915,
  3983447611, 2955280749,  399212223, 2816241238, 4099980785,
   536743428, 2418750589,   46192811, 2563456907, 1865783865,
  2502001247, 2418465150, 3727959318, 2299163660,  254372324,
   780052973,  961251919,  467607504,  366306740, 3136307309,
  1303126235,   53844018, 3813147349, 3428843266,  154512750,
  2085865906, 2970311977, 1337693374, 3622077766, 3083838012,
  2131238042, 3768171249, 2625487651, 3090263316, 1532375297,
  4199887259,  101576020, 3309404452, 1985940922,  450091477,
  1057483849, 3713926854, 3257983660, 3334084977, 2629925836,
   280111650, 2113703039, 3006333747,  542453998, 3690171023,
     3801845,    8296099,  912622081,  148887119, 1651879155,
  1026123419, 1798260024, 2966172523,  489702379,  449959780,
  1281710980, 2054314930, 3019660390, 2159327509, 2999704036,
   697491398, 3750487368, 3004223598, 1130595782, 1154934931,
  1153750941, 3820691556, 3827213413, 1073007728, 2636229698,
  1730950949, 2755271938, 4253331867, 1534046514, 1257506966,
  3780116646, 2091586294, 2341369148, 4213519444,  899335014,
  1736584005,  688525632, 2917590056, 1620438987, 2581125606,
  2780141597,  858559958, 2942106795,  371154086,  407162594,
  4290292572, 2197605099, 1240267130, 2053175997, 4183317050,
  1320598834,  993292290, 4103278010, 1562498334, 1692984308,
  1384128424, 1909362812, 2267513764,  123853952, 1548785736,
  1102719708, 2117031200, 2244341442,  915225856, 1606927859,
  3091847045, 3646891443, 2038439893, 3206824918,  906838477,
  1696272832, 2149222858, 2342415252, 4259480516, 3428739444,
   724519945, 2334220456, 3690299137, 1990859854,  300974874,
  1416707351, 3382322745, 1278688890,  166126975, 1911962375,
  2078535726,  747666142, 3858008566,  185390810, 3043418444,
   261445993, 2699391243, 2161689310, 2574378134, 3354377263,
  2544143955,  763649037, 3776531214, 2905318528, 3575985490,
  3397978929, 1611008763, 2312825127, 1449009705, 1135329820,
    64820389, 3148730756, 2660734722,  795187331, 4078153196,
  1645991882, 3058108468, 1278804422,  839027640, 2649588292,
  1720743508,  168211058, 1250870832, 1107809135, 1048218441,
   327621607, 3212506254, 1038147385,  243680578, 2349402659,
  2945508510, 2540051550,  911910508,    7594818, 2626339911,
  1868031950, 3586031610, 2305105284, 1408732842, 2171853828,
  3607830032, 1136764283,  281585067, 3983195490,  797183555,
  1215551774, 1240732668, 1569300929, 3550710012, 2529533172,
  1164910301, 1037172771, 2724522291, 3542701797, 3642402616,
  3882734393, 2053665039, 1700047834, 2428569431,  190727007,
  2944212920,   26296275, 1779797264, 3103194442, 3266947638,
  2530879061, 4263396053, 1457966369, 3585267536, 1915349633,
  1575516859, 3065632614,  504783180,  997232537, 1559766221,
  2764705009, 1658001681, 2094884399, 3416135011, 2041465872,
   135035372,  403180686, 1242179644, 1037999929,  163803024,
  2908124739,  136922982, 3024183165, 1436019727, 2030019944,
  2343364142, 1099481037, 3363602438, 2947099245, 1358725524,
  3404259002,  871815089, 1394891641, 1628543578, 2117163755,
  3881517513, 3534306129, 3964055734,  517209934, 1560428133,
  2918628387, 4160065403, 3841172074,  207035005, 3979732462,
  3940466348,  817678180, 1727127723, 2188245641,  228359806,
  3890374017, 3583577595,   46774596, 1091754348, 1072817444,
  3277735296, 4261344813, 3091174778, 3217553356, 3037777422,
  3446935975,   81481235, 1989167981,  140541700,  924374423,
  1187030773, 2215031095,  815528824, 4157862815, 2351893845,
  3323195735,  310236208, 1925780349, 1755550552,  130190545,
  2223985162, 3710763477, 2475209019,  686279544,   66816244,
  2964868731,  348651675, 2286774309,  566325740,  134866068,
  1779463561,  307845657,  196290111, 1301261954,  714609178,
  2953404602, 1728619196,  899753141, 3167399661,  692926437,
  3557154520, 2671370969,  562256973, 3902478907, 1935971403,
  3173928996, 1779580759,  873486988, 1523635120, 3422764259,
  3575580989, 1453326819,   27901296, 2291250139,  330160418,
  1031264674,  243142247, 3611259604, 2440814274, 2743034879,
   601313102,  980214665,  101109663, 3725716788, 1892455598,
  3406753354,  334348491, 4264125980, 3681402518, 3012090220,
   867975261, 2798723329,  792132230, 2112698479, 3862185041,
  3445082103,  453889473, 3444173787, 2659865050,  312498507,
  1624561144, 2445859109, 3829206971, 1563055151, 1159626440,
   724979804,  935390469,  593797546, 2169225804, 3819332313,
  4072000517, 3098594556, 2958605051,  988429804,  218269316,
  1689194479,  554645797, 3061760314, 2534829332, 4158770640,
  1524326631, 3576258236,  679687458, 1626187994, 2076665873,
  2896160413,  816550892,   57239060,  367240633, 3972390033,
   490442391, 1920328311, 1401823054, 1823565787, 2812474370,
   766729726, 2830942765, 3636824682, 1783798539,  265566563,
  2948692631, 2486975604, 2501085033, 1867384690, 2974004872,
   991487826, 1775428782, 2164771327, 3451675362, 1468088655,
  2340897662, 2802716929, 2447031397, 1310928080,  580340149,
  3610798086, 3015963211, 1625051655,  198941744,  443607017,
  4085019093, 1152949000, 3033725302, 3020826556, 4292840064,
  2621512234, 3505894269, 4015247044, 3970225546,  194130432,
  3475169380, 2394923779, 4157571404,  850274859, 3051437486,
  3382245887,  882460592,  701461198,  400789381, 4088553769,
  3562892673,  162778776, 2248488632, 3849924123,  313353241,
  4126612585, 3418929090, 2405766745, 2697753843, 3616323998,
  1371573635,  703943753,    3069715,  950543603, 1461067254,
  1951589145,  629739054, 3343131699, 1247765333, 1787027936,
  2185031094, 4057220331, 2285375639, 1575187518, 1187663770,
  3627484295, 3991672138, 1128209147, 4126856527, 2564501428,
  3829983597, 4132496584, 1270198057, 2642763401, 3310147931,
  1188650149, 4017355760, 4181980786, 2260357759, 2643269896,
  4080077970,   87297557,  131070681,  568480894, 2350378992,
  3542868064, 2327461883, 2496921893, 3316152136, 2186027017,
  1942021986, 3456025263,  241979827, 2825881438, 3160502983,
  4159935985, 1064663475, 2057377005,  375066645, 3576763930,
  3815699899, 3692379743,  487372827, 3472867655, 1618601166,
  3272879503, 2786566275, 3041914223, 3284647468,   39930559,
  1874185814, 3525212524,  755598814, 3925360995, 3248954940,
   679991663, 1472514341,   99607188, 2283106643, 2586887400,
  2287247521,   38813565,  215412609,  497349210, 3908712544,
   853774963, 1283871446, 2595464239, 2662170480, 2204991491,
  1824422197, 1913979613, 1514698076,  122256558, 3729141581,
  2465562279,  534932704,  667427458, 3605802795, 2160518146,
  3464953340, 1382325612, 3348688967, 1169876486, 2300243017,
  1724478272, 2628017692, 1116103068, 4126788667, 1317157587,
  3235238954, 2934018198, 1028035331, 4266439552, 3385688204,
   933854710,  814707999,  661516468, 3858479559, 2546606192,
);

plan tests => scalar(@results);

my $rng = Math::Random::ISAAC::PP->new();

foreach my $num (@results) {
  ok($num == $rng->randInt());
}
