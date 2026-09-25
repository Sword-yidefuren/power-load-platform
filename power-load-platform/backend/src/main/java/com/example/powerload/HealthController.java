package com.example.powerload;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 环境自检接口 —— 用来证明"Spring Boot -> MySQL"这条链路是通的。
 *
 * 访问 http://localhost:8080/api/health 应当返回数据库信息。
 */
@RestController
@RequestMapping("/api")
public class HealthController {

    private final DataSource dataSource;

    // 构造器注入：Spring 启动时自动把数据源塞进来
    public HealthController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("status", "UP");
        result.put("message", "Spring Boot 已启动，数据库连接正常");

        try (Connection conn = dataSource.getConnection();
             Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery("SELECT VERSION() AS v, DATABASE() AS db")) {

            if (rs.next()) {
                result.put("mysqlVersion", rs.getString("v"));
                result.put("database", rs.getString("db"));
            }

            // 顺便数一下表里有几行，证明真的读到了业务数据
            try (Statement st2 = conn.createStatement();
                 ResultSet rs2 = st2.executeQuery("SELECT COUNT(*) AS c FROM load_record")) {
                if (rs2.next()) {
                    result.put("loadRecordRows", rs2.getInt("c"));
                }
            }

        } catch (Exception e) {
            result.put("status", "DOWN");
            result.put("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }

        return result;
    }
}
