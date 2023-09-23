#include <iostream>
#include <string>
#include <stdlib.h>
#include <stdio.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>
#include <fstream>
#include "lib/paper.h"

using json = nlohmann::json;

int main(void)
{
  downloadpaper();
  return 0;
}
