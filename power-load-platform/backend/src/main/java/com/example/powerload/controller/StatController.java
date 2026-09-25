package com.example.powerload.controller;

import com.example.powerload.entity.LoadDailyStat;
import com.example.powerload.dto.RegionSummaryDTO;
import com.example.powerload.service.StatService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 第 5 步 · 统计接口
 *
 * 五个接口，从"读现成的统计表"到"实时聚合"，逐个看：
 *
 *   GET /api/stats/daily               读 load_daily_stat 全部
 *   GET /api/stats/daily?regionCode=GD-01
 *   GET /api/stats/region-summary      ★ GROUP BY 聚合 -> DTO
 *   GET /api/stats/region-detail       聚合 + Java 算派生指标（峰谷差、负荷率）
 *   GET /api/stats/by-date             按日期聚合
 */
@RestController
@RequestMapping("/api/stats")
public class StatController {

    private final StatService statService;

    public StatController(StatService statService) {
        this.statService = statService;
    }

    /** 读"已经算好的"日统计表 */
    @GetMapping("/daily")
    public Map<String, Object> daily(
            @RequestParam(value = "regionCode", required = false) String regionCode) {

        List<LoadDailyStat> rows = (regionCode == null || regionCode.isBlank())
                ? statService.dailyStatAll()
                : statService.dailyStatByRegion(regionCode);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", rows.size());
        result.put("data", rows);
        return result;
    }

    /**
     * ★ 实时聚合：GROUP BY region_name
     * 返回的就是 DTO 的字段，前端拿到的每个对象都有明确字段名。
     */
    @GetMapping("/region-summary")
    public Map<String, Object> regionSummary() {
        List<RegionSummaryDTO> rows = statService.summarizeByRegion();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", rows.size());
        result.put("data", rows);
        return result;
    }

    /** 聚合 + 业务派生指标（峰谷差、负荷率） */
    @GetMapping("/region-detail")
    public Map<String, Object> regionDetail() {
        List<Map<String, Object>> rows = statService.regionSummaryWithDerived();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", rows.size());
        result.put("data", rows);
        return result;
    }

    /** 按日期聚合 */
    @GetMapping("/by-date")
    public Map<String, Object> byDate() {
        List<Map<String, Object>> rows = statService.summarizeByDate();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", rows.size());
        result.put("data", rows);
        return result;
    }
}
