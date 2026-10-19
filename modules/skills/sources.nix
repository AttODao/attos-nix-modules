# Pinned skill repositories; Pi's ponytail extension reuses the same pin.
{ pkgs }:
{
  mattSkills = pkgs.fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "49dd158d1076134a641b33efb035946536778336";
    hash = "sha256-NljCSZNI3sZ+vbCw7pRdrwR7try4BxOFp4gdjuWYtzs=";
  };
  vercelSkills = pkgs.fetchFromGitHub {
    owner = "vercel-labs";
    repo = "skills";
    rev = "13e4063a1cf913f5606d57d42ab83a86f5001e04";
    hash = "sha256-djzSciYX530uc1Xk4+Vdf2IHmNotC0bb6YU/peF0UK4=";
  };
  ponytail = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "v5.3.2";
    hash = "sha256-IJlhfkdXI6pMZZCZO7XBRg88LBiNfzc5Gnm4ofGybL8=";
  };
}
