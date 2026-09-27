package com.example.powerload.controller;

import com.example.powerload.service.ForecastService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 第 7 步 · 预测结果接口
 *
 *   GET /api/forecast                 所有地区的预测曲线
 *   GET /api/forecast?regionCode=GD-01 指定地区
 *   GET /api/forecast/overview         概览（预测点数、地区数、模型 R²）
 *
 * 数据来源是 Python 脚本写进 load_forecast 表的结果 ——
 * 也就是说这个接口展示了"算法 → 数据库 → 后端 → 前端"里的后两段。
 */
@RestController
@RequestMapping("/api/forecast")
public class ForecastController {

    private final ForecastService service;

    public ForecastController(ForecastService service) {
        this.service = service;
    }

    @GetMapping
    public Map<String, Object> forecast(
            @RequestParam(value = "regionCode", required = false) String regionCode) {

        List<Map<String, Object>> series = service.getForecastSeries(regionCode);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", series.size());
        result.put("data", series);
        // 明确告诉调用方这份数据的性质，避免被当成"真实准确预测"
        result.put("disclaimer", "线性回归演示模型，训练数据仅 8 条，不代表真实预测能力");
        return result;
    }

    @GetMapping("/overview")
    public Map<String, Object> overview() {
        return service.getForecastOverview();
    }
}
