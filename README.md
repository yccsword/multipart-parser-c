## Multipart form data parser

### Features
* No dependencies
* Works with chunks of a data - no need to buffer the whole request
* Almost no internal buffering. Buffer size doesn't exceed the size of the boundary (~60-70 bytes)

Tested as part of [Cosmonaut](https://github.com/iafonov/cosmonaut) HTTP server.

Implementation based on [node-formidable](https://github.com/felixge/node-formidable) by [Felix Geisendörfer](https://github.com/felixge).

Inspired by [http-parser](https://github.com/joyent/http-parser) by [Ryan Dahl](https://github.com/ry).

### Usage (C)
This parser library works with several callbacks, which the user may set up at application initialization time.

```c
multipart_parser_settings callbacks;

memset(&callbacks, 0, sizeof(multipart_parser_settings));

callbacks.on_header_field = read_header_name;
callbacks.on_header_value = read_header_value;
callbacks.on_part_data = write_part;
callbacks.on_part_data_begin = start_data_write;
callbacks.on_part_data_end = end_data_write;
callbacks.on_body_end = parse_end;
```

These functions must match the signatures defined in the multipart-parser header file.  For this simple example, we'll just use two of the available callbacks to print all headers the library finds in multipart messages.

Returning a value other than 0 from the callbacks will abort message processing.

```c
int start_data_write(multipart_parser* p)
{return 0;}

int end_data_write(multipart_parser* p)
{
	if (filepath != NULL)
	{
		free(filepath);
		filepath = NULL;
		uploadfile_count++;
	}
	return 0;
}

int parse_end (multipart_parser* p)
{
	if (filepath != NULL)
	{
		free(filepath);
		filepath = NULL;
	}
	return 0;
}

int read_header_name(multipart_parser* p, const char *at, size_t length)
{
   printf("%.*s: ", length, at);
   return 0;
}

int read_header_value(multipart_parser* p, const char *at, size_t length)
{
	char * filename = strstr(at, "filename=");//获取filename位置的指针地址
	unsigned int prefix_len = (filename > at) ? (filename - at) : (at - filename);//获取content-head中filename前的数据长度
	int filename_len = (length >= prefix_len + 9) ? (length - prefix_len - 9) : -1;//获取filename长度
	char * form_dataname = NULL;

	//由于at指针携带是整个post content的内容，如果filedata不是在这个head下，需要转form-data处理
	if (filename != NULL && filename_len >= 0)
	{
		if (uploadfile_count >= MAX_UPLOADFILE_COUNT)
		{
			FCGI_ErrLog("Max upload file onetime is %d,please upload %s next time.\n", MAX_UPLOADFILE_COUNT, filename);
			return 0;
		}
		if (filename_len >= MAX_UPLOADFILE_NAME_LEN)
		{
			FCGI_ErrLog("Max upload filename len is %d,file ", MAX_UPLOADFILE_NAME_LEN - 3);
			fwrite((void *)filename + 9, filename_len, 1, stderr);
			fprintf(stderr," name len is %d too long.\n", filename_len - 2);
			return 0;
		}
		memcpy(uploadfile_name[uploadfile_count], filename + 9, filename_len);
		trim(uploadfile_name[uploadfile_count], '\"');
		//if (uploadfile_name[uploadfile_count] == NULL) {FCGI_ErrLog("uploadfile_name[%d] is NULL!\n", uploadfile_count);return 0;}
		int uploadfile_name_len = strlen(uploadfile_name[uploadfile_count]);
		if (uploadfile_name_len == 0) {FCGI_ErrLog("uploadfile_name_len is 0!\n");return 0;}
		int filepath_prefix_len = strlen(UPLOAD_FILE_PREFIX);
		filepath = calloc(1, filepath_prefix_len + MAX_UPLOADFILE_NAME_LEN);
		if (filepath == NULL) {FCGI_ErrLog("filepath calloc error!\n");return 0;}
		memcpy(filepath, UPLOAD_FILE_PREFIX, filepath_prefix_len);
		memcpy(filepath + filepath_prefix_len, uploadfile_name[uploadfile_count], uploadfile_name_len);
		filepath[filepath_prefix_len + uploadfile_name_len] = '\0';
	}
	//form-data只能作为该条记录的开始
	else if (strstr(at, "form-data;") != NULL && (form_dataname = strstr(at, "name=")) != NULL && (form_dataname - at) <= length)
	{
		unsigned int form_dataname_prefix_len = form_dataname - at;
		int form_dataname_len = length - form_dataname_prefix_len - 5;
		char * last_post_form_data = post_form_data;

		char * real_form_dataname = alloca(form_dataname_len + 1);
		if (real_form_dataname == NULL) {FCGI_ErrLog("real_form_dataname alloca error!drop %.*s data.\n", length, at);return 0;}
		memcpy(real_form_dataname, form_dataname + 5, form_dataname_len);
		real_form_dataname[form_dataname_len] = '\0';
		trim(real_form_dataname, '\"');
		int real_form_dataname_len = strlen(real_form_dataname);
		unsigned int new_post_form_data_len = post_form_data_len + real_form_dataname_len + 2;
		
		post_form_data = (char *)realloc(last_post_form_data, new_post_form_data_len);
		if (post_form_data == NULL)
		{
			post_form_data = last_post_form_data;
			FCGI_ErrLog("realloc post_form_data error! drop %.*s data.\n", length, at);
			return 0;
		}

		FCGI_ErrLog("real_form_dataname:%s ", real_form_dataname);
		
		post_form_data[(post_form_data_len == 0) ? 0 : (post_form_data_len - 1)] = '&';
		memcpy(post_form_data + post_form_data_len, real_form_dataname, real_form_dataname_len);
		post_form_data[new_post_form_data_len - 2] = '=';
		post_form_data[new_post_form_data_len - 1] = '\0';
		post_form_data_len = new_post_form_data_len;
		FCGI_ErrLog("%.*s: ", length, at);
		FCGI_ErrLog("post_form_data:%s post_form_data_len:%d", post_form_data, post_form_data_len);
	}
	return 0;
}

int write_part(multipart_parser* p, const char *at, size_t length)
{
	if (filepath == NULL) 
	{
		if (post_form_data != NULL)
		{
			if (post_form_data[post_form_data_len - 2] == '=')
			{
				char * last_post_form_data = post_form_data;
				unsigned int new_post_form_data_len = post_form_data_len + length;
				post_form_data = (char *)realloc(last_post_form_data, new_post_form_data_len);
				if (post_form_data == NULL)
				{
					post_form_data = last_post_form_data;
					FCGI_ErrLog("realloc post_form_data error! drop %.*s data part.\n", length, at);
					return 0;
				}
				memcpy(post_form_data + post_form_data_len - 1, at, length);
				post_form_data[new_post_form_data_len - 1] = '\0';
				post_form_data_len = new_post_form_data_len;
				FCGI_ErrLog("post_form_data:%s post_form_data_len:%d", post_form_data, post_form_data_len);
			}
			FCGI_ErrLog("%.*s \n", length, at);
		}
		else
		{
			FCGI_ErrLog("this part not a file and not a form data, please check!\n");
		}
		return 0;
	}
	if (uploadfile_count >= MAX_UPLOADFILE_COUNT)
	{
		FCGI_ErrLog("Max upload file onetime is %d,this file will drop.\n", MAX_UPLOADFILE_COUNT);
		return 0;
	}
	FILE *fp = NULL;
	if ((fp = fopen(filepath, "ab+")) == NULL)
	{
		FCGI_ErrLog("Write uploadfile open fp fail!\n");
		return 0;
	}
	fwrite((void *)at, length, 1, fp);
	fflush(fp);  
	fclose(fp);
	return 0;
}
```

When a message arrives, callers must parse the multipart boundary from the **Content-Type** header (see the [RFC](http://tools.ietf.org/html/rfc2387#section-5.1) for more information and examples), and then execute the parser.

```c
multipart_parser* parser = multipart_parser_init(boundary, &callbacks);
multipart_parser_execute(parser, body, length);
multipart_parser_free(parser);
```

/*--${bound}*/
```c
bound = strstr(http_env[CONTENT_TYPE], "boundary=") + 9;
boundlen = strlen(bound);
__bound = alloca(boundlen + 2);
if(__bound == NULL){FCGI_ErrLog("alloca __bound error! abort parse multipart/form-data.\n");return &wp;}
memcpy(__bound, "--", 2);memcpy(__bound + 2, bound, boundlen);
__bound[boundlen + 2] = '\0';
parser = multipart_parser_init(__bound, &callbacks);
if (wp.content_length != (multipart_parser_execute_len = multipart_parser_execute(parser, wp.content, wp.content_length)))
{
	FCGI_ErrLog("%s CONTENT_LENGTH:%d multipart_parser_execute_len:%d not equal! multipart_parser_execute not Complete!\n",
				http_env[CONTENT_TYPE], wp.content_length, multipart_parser_execute_len);
}
```

### Usage (C++)
In C++, when the callbacks are static member functions it may be helpful to pass the instantiated multipart consumer along as context.  The following (abbreviated) class called `MultipartConsumer` shows how to pass `this` to callback functions in order to access non-static member data.

```cpp
class MultipartConsumer
{
public:
    MultipartConsumer(const std::string& boundary)
    {
        memset(&m_callbacks, 0, sizeof(multipart_parser_settings));
        m_callbacks.on_header_field = ReadHeaderName;
        m_callbacks.on_header_value = ReadHeaderValue;

        m_parser = multipart_parser_init(boundary.c_str(), &m_callbacks);
        multipart_parser_set_data(m_parser, this);
    }

    ~MultipartConsumer()
    {
        multipart_parser_free(m_parser);
    }

    int CountHeaders(const std::string& body)
    {
        multipart_parser_execute(m_parser, body.c_str(), body.size());
        return m_headers;
    }

private:
    static int ReadHeaderName(multipart_parser* p, const char *at, size_t length)
    {
        MultipartConsumer* me = (MultipartConsumer*)multipart_parser_get_data(p);
        me->m_headers++;
    }

    multipart_parser* m_parser;
    multipart_parser_settings m_callbacks;
    int m_headers;
};
```

### Contributors
* [Daniel T. Wagner](http://www.danieltwagner.de/)
* [James McLaughlin](http://udp.github.com/)
* [Jay Miller](http://www.cryptofreak.org)

© 2017 [yccsword](http://yccsword.github.com)
