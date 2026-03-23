#include <curl/curl.h>
#include <stdlib.h>
#include <string.h>

struct buffer {
    char *data;
    size_t size;
};

static size_t write_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    struct buffer *mem = (struct buffer *)userp;
    char *ptr = (char *)realloc(mem->data, mem->size + realsize + 1);
    if (!ptr) return 0;
    mem->data = ptr;
    memcpy(&(mem->data[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->data[mem->size] = '\0';
    return realsize;
}

static char *dup_empty(void) {
    char *p = (char *)malloc(1);
    if (p) p[0] = '\0';
    return p;
}

static char *do_request(const char *url, const char *auth_header, const char *json_body, long *status_code, size_t *out_len) {
    CURL *curl;
    CURLcode res;
    struct curl_slist *headers = NULL;
    struct buffer chunk = {0};
    char *result = NULL;

    if (status_code) *status_code = 0;
    if (out_len) *out_len = 0;

    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl = curl_easy_init();
    if (!curl) return dup_empty();

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 20L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "fortransky/0.7");
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");

    if (auth_header && auth_header[0] != '\0') headers = curl_slist_append(headers, auth_header);
    if (json_body) {
        headers = curl_slist_append(headers, "Content-Type: application/json");
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json_body);
    }
    if (headers) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    res = curl_easy_perform(curl);
    if (res == CURLE_OK) {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, status_code);
        result = chunk.data ? chunk.data : dup_empty();
        if (out_len && result) *out_len = strlen(result);
    } else {
        const char *msg = curl_easy_strerror(res);
        result = (char *)malloc(strlen(msg) + 1);
        if (result) strcpy(result, msg);
        if (out_len && result) *out_len = strlen(result);
        free(chunk.data);
    }

    if (headers) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result ? result : dup_empty();
}

char *fortransky_http_get(const char *url, const char *auth_header, long *status_code, size_t *out_len) {
    return do_request(url, auth_header, NULL, status_code, out_len);
}

char *fortransky_http_post_json(const char *url, const char *auth_header, const char *json_body, long *status_code, size_t *out_len) {
    return do_request(url, auth_header, json_body, status_code, out_len);
}

/* Upload raw binary data (e.g. PNG blob) with a given Content-Type.
   Used for com.atproto.repo.uploadBlob. */
char *fortransky_http_post_binary(const char *url, const char *auth_header,
                                  const char *content_type,
                                  const unsigned char *data, size_t data_len,
                                  long *status_code, size_t *out_len) {
    CURL *curl;
    CURLcode res;
    struct curl_slist *headers = NULL;
    struct buffer chunk = {0};
    char *result = NULL;
    char ct_header[256];

    if (status_code) *status_code = 0;
    if (out_len)     *out_len     = 0;

    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl = curl_easy_init();
    if (!curl) return dup_empty();

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 60L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "fortransky/1.2");
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");

    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)data_len);

    if (auth_header && auth_header[0] != '\0')
        headers = curl_slist_append(headers, auth_header);

    snprintf(ct_header, sizeof(ct_header), "Content-Type: %s", content_type);
    headers = curl_slist_append(headers, ct_header);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    res = curl_easy_perform(curl);
    if (res == CURLE_OK) {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, status_code);
        result = chunk.data ? chunk.data : dup_empty();
        if (out_len && result) *out_len = strlen(result);
    } else {
        const char *msg = curl_easy_strerror(res);
        result = (char *)malloc(strlen(msg) + 1);
        if (result) strcpy(result, msg);
        if (out_len && result) *out_len = strlen(result);
        free(chunk.data);
    }

    if (headers) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result ? result : dup_empty();
}

void fortransky_http_free(char *ptr) {
    free(ptr);
}
