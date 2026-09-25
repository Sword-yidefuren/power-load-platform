package com.example.powerload.service;

import com.example.powerload.entity.LoadRecord;
import com.example.powerload.repository.LoadRecordRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

/**
 * 第 4 步 · 服务层（Service）—— 餐厅的"厨师"
 *
 * 这一层是干什么的？很多人会问："Controller 直接调 Repository 不行吗？"
 * 行，但会出问题。Service 存在的理由：
 *
 *   1. 放"业务规则"。比如"负荷超过 1.5 倍日均值算异常"这种判断，
 *      它既不属于"接 HTTP 请求"，也不属于"读写数据库"，两边都不该放，
 *      只能放中间这一层。
 *   2. 被多处复用。以后 Vue 页面和 Python 脚本都要"按地区查负荷"，
 *      都调同一个 Service，规则只写一遍。
 *   3. 事务边界。见下面 @Transactional 的说明。
 *
 * @Service 这个注解的作用：告诉 Spring"启动时把这个类也创建好、管起来"，
 * 这样 Controller 需要它的时候，Spring 能直接送过去（依赖注入）。
 */
@Service
public class LoadRecordService {

    private final LoadRecordRepository repository;

    /**
     * 构造器注入：和 HealthController 里的 DataSource 一样，
     * Spring 启动时自动把 repository 塞进来，不用自己 new。
     */
    public LoadRecordService(LoadRecordRepository repository) {
        this.repository = repository;
    }

    /**
     * @Transactional(readOnly = true) 是什么意思？
     *
     * 事务（Transaction）人话版 = "一组要么全成、要么全不成的操作"。
     * 转账就是经典例子：扣钱和加钱必须一起成功，不能扣了钱没加上。
     *
     * 加在"只读"方法上的 readOnly = true，是在告诉数据库：
     *   "我这次只查不改，你不用给我准备写锁、也别记回滚日志。"
     * 数据库因此可以跑得更快。
     *
     * 面试可以这么说："查询方法我会标 readOnly，让数据库走只读优化，
     * 同时避免有人误在这个方法里写数据。"
     */
    @Transactional(readOnly = true)
    public List<LoadRecord> findAll() {
        return repository.findAll();
    }

    @Transactional(readOnly = true)
    public List<LoadRecord> findByRegionName(String regionName) {
        // 业务规则写在 Service：regionName 为空时给一个默认值，别把 null 透传给数据库
        String region = (regionName == null || regionName.isBlank()) ? "广州" : regionName.trim();
        return repository.findByRegionNameOrderByTsAsc(region);
    }

    @Transactional(readOnly = true)
    public List<LoadRecord> findHighLoad(BigDecimal threshold) {
        // 业务规则：传负数或 0 没有意义，兜底成 10000
        BigDecimal min = (threshold == null || threshold.signum() <= 0)
                ? new BigDecimal("10000")
                : threshold;
        return repository.findByLoadKwGreaterThanOrderByLoadKwDesc(min);
    }

    @Transactional(readOnly = true)
    public List<LoadRecord> findAnomalies() {
        return repository.findByIsAnomaly(1);
    }

    @Transactional(readOnly = true)
    public List<LoadRecord> findByLoadRange(String regionName, BigDecimal minLoad, BigDecimal maxLoad) {
        return repository.findByLoadRange(regionName, minLoad, maxLoad);
    }

    /** 全表行数 —— 用来验证接口读到的确实是数据库里的数据 */
    @Transactional(readOnly = true)
    public long count() {
        return repository.count();
    }
}
