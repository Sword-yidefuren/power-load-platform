package com.example.powerload;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 第 3 步：你的第一个接口。
 *
 * 这个类故意不碰数据库 —— 先专心搞清楚
 * "浏览器发一个请求，后端怎么把结果送回去" 这条链路。
 *
 * 可访问的地址（注意 /api 和 /hello 是怎么拼起来的）：
 *   http://127.0.0.1:8080/api/hello
 *   http://127.0.0.1:8080/api/hello?name=ZhangSan
 *   http://127.0.0.1:8080/api/hello?name=ZhangSan&region=GuangZhou
 */
@RestController
@RequestMapping("/api")
public class GreetingController {

    /** 时间格式化器：把时间对象变成 "2026-09-23 22:30:15" 这样的字符串 */
    private static final DateTimeFormatter FMT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @GetMapping("/hello")
    public Map<String, Object> hello(
            // required = false 表示这个参数可以不传；不传时用默认值 "world"
            @RequestParam(value = "name", required = false, defaultValue = "world") String name,
            @RequestParam(value = "region", required = false, defaultValue = "广州") String region) {

        // LinkedHashMap：一个"键值对"容器，插入顺序就是最终 JSON 里的字段顺序
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("message", "你好，" + name + "！这是你的第一个 Spring Boot 接口");
        result.put("region", region);
        result.put("serverTime", LocalDateTime.now().format(FMT));

        // 返回 Map，Spring 会自动把它转成 JSON
        return result;
    }
}
