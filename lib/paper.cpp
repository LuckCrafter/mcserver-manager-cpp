#include <iostream>
#include <string>
#include <stdlib.h>
#include <stdio.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>
#include <fstream>
#include "paper.h"

using json = nlohmann::json;

static size_t WriteCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
    ((std::string*)userp)->append((char*)contents, size * nmemb);
    return size * nmemb;
}
std::string download(std::string const& url) {
  CURL *curl;
  curl = curl_easy_init();
  if (!curl) return "failed";
  CURLcode res;
  std::string readBuffer;
  curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &readBuffer);
  res = curl_easy_perform(curl);
  curl_easy_cleanup(curl);
  return readBuffer;
}

void downloadpaper() {
  json j = json::parse(download("https://api.papermc.io/v2/projects/paper/"));
  std::string version = j["versions"][j["versions"].size()-1];
  downloadpaper(version);
}

void downloadpaper(std::string version) {
  json j = json::parse(download("https://api.papermc.io/v2/projects/paper/versions/"+version));
  int build = j["builds"][j["builds"].size()-1];
  downloadpaper(version, std::to_string(build));
}

void downloadpaper(std::string version, std::string build) {
  std::string file = "paper-"+version+"-"+build+".jar";
  std::ofstream downloadfile(file);
  downloadfile << download("https://api.papermc.io/v2/projects/paper/versions/"+version+"/builds/"+build+"/downloads/"+file);
  downloadfile.close();
}