package com.example.powerload.controller;

import com.example.powerload.entity.LoadRecord;
import com.example.powerload.service.LoadRecordService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 第 4 步 · 控制层（Controller）—— 餐厅的"服务员"
 *
 * 对比第 0 步的 HealthController：那个类里直接写了 SQL（服务员跑进仓库搬箱子）。
 * 这个类是"规矩"的写法：
 *
 *     Controller  ->  只接单、只返回
 *        调 Service
 *     Service     ->  只写业务规则 + 事务
 *        调 Repository
 *     Repository  ->  只有它跟数据库打交道
 *
 * 一个判断标准：Controller 里出现 SQL、或者出现"如果...就算异常"这种业务判断，
 * 就说明分层被破坏了。
 */
@RestController
@RequestMapping("/api")
public class LoadRecordController {

    private final LoadRecordService service;

    public LoadRecordController(LoadRecordService service) {
        this.service = service;
    }

    /**
     * GET /api/load-records
     * GET /api/load-records?region=深圳
     *
     * 返回示例：
     *   { "count": 8,
     *     "data": [ { "id": 1, "regionName": "广州", "loadKw": 8120.500, ... }, ... ] }
     */
    @GetMapping("/load-records")
    public Map<String, Object> list(
            @RequestParam(value = "region", required = false) String region) {

        // 有 region 参数就按地区查，没传就查全部
        List<LoadRecord> rows = (region == null || region.isBlank())
                ? service.findAll()
                : service.findByRegionName(region);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", rows.size());   // 条数放前面，一眼能看出查没查到
        result.put("data", rows);           // 实体对象列表，Spring 自动转成 JSON 数组
        return result;
    }

    /**
     * GET /api/load-records/high?threshold=10000
     * 查高负荷记录 —— 就是你在第 1 步用 SQL 练过的那件事
     */
    @GetMapping("/load-records/high")
    public Map<String, Object> high(
            @RequestParam(value = "threshold", required = false, defaultValue = "10000") BigDecimal threshold) {

        List<LoadRecord> rows = service.findHighLoad(threshold);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("threshold", threshold);
        result.put("count", rows.size());
        result.put("data", rows);
        return result;
    }

    /**
     * GET /api/load-records/anomalies
     * 只查算法判定为异常的点（is_anomaly = 1）
     *
     * 注意这个地址和上面 /load-records 的关系：
     * Spring 会优先匹配更具体的路径，所以 /load-records/anomalies 不会被
     * 当成 "region=anomalies" 处理。
     */
    @GetMapping("/load-records/anomalies")
    public Map<String, Object> anomalies() {
        List<LoadRecord> rows = service.findAnomalies();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", rows.size());
        result.put("data", rows);
        return result;
    }

    /**
     * GET /api/load-records/range?region=广州&min=7000&max=13000
     * 用 @Query 里自定义的那段 SQL 查负荷区间
     */
    @GetMapping("/load-records/range")
    public Map<String, Object> range(
            @RequestParam(value = "region", required = false, defaultValue = "广州") String region,
            @RequestParam(value = "min", required = false, defaultValue = "0") BigDecimal min,
            @RequestParam(value = "max", required = false, defaultValue = "99999999") BigDecimal max) {

        List<LoadRecord> rows = service.findByLoadRange(region, min, max);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("region", region);
        result.put("min", min);
        result.put("max", max);
        result.put("count", rows.size());
        result.put("data", rows);
        return result;
    }

    /**
     * GET /api/load-records/count
     * 只返回总数 —— 用来快速验证"接口读的确实是数据库"
     */
    @GetMapping("/load-records/count")
    public Map<String, Object> count() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("totalRows", service.count());
        return result;
    }
}
