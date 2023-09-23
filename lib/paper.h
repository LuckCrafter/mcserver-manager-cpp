#include <iostream>
#include <string>
#include <stdlib.h>
#include <stdio.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>
#include <fstream>

std::string download(std::string const& url);

void downloadpaper();
void downloadpaper(std::string version);
void downloadpaper(std::string version, std::string build);