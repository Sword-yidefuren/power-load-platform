package com.example.powerload.service;

import com.example.powerload.dto.ForecastPointDTO;
import com.example.powerload.entity.LoadForecast;
import com.example.powerload.repository.LoadForecastRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 第 7 步 · 预测结果服务
 *
 * 这一层要干的事比前几步更"业务"：
 *   1. 从数据库读出 Python 写的预测结果
 *   2. 标注哪些点属于"模型外推"（历史没见过的时刻），前端可以据此弱化显示
 *   3. 算预测的峰谷差、负荷率 —— 和 StatService 里对实际数据做的是同一套指标
 *
 * 值得注意的设计：**"哪些小时算外推"这个判断放在 Java 侧，而不是 Python 侧。**
 * 因为它是"对外解释数据可信度"的逻辑，属于接口语义的一部分；
 * Python 脚本只管算模型。职责分离更清楚。
 */
@Service
public class ForecastService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    /**
     * 历史数据里真实观测到的小时。
     *
     * 这里先写死，因为它是"当前这份数据集"的属性。
     * 更正规的做法是从 load_record 里动态查出来：
     *     SELECT DISTINCT HOUR(ts) FROM load_record
     * —— 留作改进点，面试被问到"这个写死的常量怎么改进"时可以答这个。
     */
    private static final Set<Integer> OBSERVED_HOURS =
            new HashSet<>(Arrays.asList(0, 1, 2, 12, 14));

    private final LoadForecastRepository repository;

    public ForecastService(LoadForecastRepository repository) {
        this.repository = repository;
    }

    /**
     * 取预测曲线，按地区分组。
     *
     * @param regionCode 地区编码，为空则返回所有地区
     */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> getForecastSeries(String regionCode) {
        List<LoadForecast> rows = (regionCode == null || regionCode.isBlank())
                ? repository.findAllByOrderByRegionCodeAscForecastTsAsc()
                : repository.findByRegionCodeOrderByForecastTsAsc(regionCode.trim());

        // 按地区分组，每组一个 { regionCode, regionName, modelR2, points: [...] }
        Map<String, Map<String, Object>> grouped = new LinkedHashMap<>();

        for (LoadForecast f : rows) {
            Map<String, Object> group = grouped.computeIfAbsent(f.getRegionCode(), k -> {
                Map<String, Object> g = new LinkedHashMap<>();
                g.put("regionCode", f.getRegionCode());
                g.put("regionName", f.getRegionName());
                g.put("modelName", f.getModelName());
                g.put("modelR2", f.getModelR2());
                g.put("points", new ArrayList<ForecastPointDTO>());
                return g;
            });

            boolean extrapolated = f.getInputHour() == null
                    || !OBSERVED_HOURS.contains(f.getInputHour());

            @SuppressWarnings("unchecked")
            List<ForecastPointDTO> points = (List<ForecastPointDTO>) group.get("points");
            points.add(new ForecastPointDTO(
                    f.getForecastTs().format(FMT),
                    f.getPredictedLoad(),
                    f.getInputTemp(),
                    extrapolated));
        }

        // 给每组装上业务指标（峰谷差、负荷率），和 StatService 的口径保持一致
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> group : grouped.values()) {
            @SuppressWarnings("unchecked")
            List<ForecastPointDTO> points = (List<ForecastPointDTO>) group.get("points");
            group.putAll(metrics(points));
            result.add(group);
        }
        return result;
    }

    /** 预测总数与地区数 —— 前端可用来判断"预测跑过没有" */
    @Transactional(readOnly = true)
    public Map<String, Object> getForecastOverview() {
        List<LoadForecast> all = repository.findAll();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totalPoints", all.size());
        out.put("regionCount", all.stream().map(LoadForecast::getRegionCode).distinct().count());
        if (!all.isEmpty()) {
            out.put("firstTime", all.get(0).getForecastTs().format(FMT));
            out.put("modelR2", all.get(0).getModelR2());
        }
        out.put("note", "预测结果由 Python 线性回归脚本写入，数据量仅 8 条，仅供流程演示");
        return out;
    }

    /**
     * 从预测点里算业务指标。
     * 和 StatService 里对实际数据算的是一套口径 —— 这样"预测"和"实际"才能对比。
     */
    private Map<String, Object> metrics(List<ForecastPointDTO> points) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (points.isEmpty()) {
            return m;
        }

        BigDecimal max = null;
        BigDecimal min = null;
        BigDecimal sum = BigDecimal.ZERO;
        int extrapolatedCount = 0;

        for (ForecastPointDTO p : points) {
            BigDecimal v = p.getPredictedLoad();
            if (v == null) {
                continue;
            }
            max = (max == null || v.compareTo(max) > 0) ? v : max;
            min = (min == null || v.compareTo(min) < 0) ? v : min;
            sum = sum.add(v);
            if (p.isExtrapolated()) {
                extrapolatedCount++;
            }
        }

        if (max == null) {
            return m;
        }

        BigDecimal avg = sum.divide(BigDecimal.valueOf(points.size()), 3, RoundingMode.HALF_UP);
        m.put("pointCount", points.size());
        m.put("avgLoad", avg);
        m.put("peakLoad", max);
        m.put("valleyLoad", min);
        m.put("peakValleyDiff", max.subtract(min));
        m.put("loadRate", max.signum() > 0
                ? avg.divide(max, 4, RoundingMode.HALF_UP)
                : BigDecimal.ZERO);
        // 把"外推点占比"作为可信度提示暴露出去
        m.put("extrapolatedCount", extrapolatedCount);
        m.put("extrapolatedRatio", BigDecimal.valueOf(extrapolatedCount)
                .divide(BigDecimal.valueOf(points.size()), 4, RoundingMode.HALF_UP));
        return m;
    }
}
