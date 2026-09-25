package com.example.powerload.repository;

import com.example.powerload.entity.LoadRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;

/**
 * 第 4 步 · 仓库层（Repository / DAO）—— 餐厅的"库管"
 *
 * ★★★ 重点：这是一个接口，你没有写它的实现类！ ★★★
 *
 * 那谁实现了它？Spring Data JPA 在启动时"扫描 + 动态生成"了一个实现类。
 * 你继承 JpaRepository 之后，白送这些方法（不用写一行代码）：
 *
 *      findAll()                 查全部
 *      findById(id)              按主键查一个，返回 Optional
 *      save(entity)              新增或更新
 *      deleteById(id)            按主键删
 *      count()                   总数
 *      existsById(id)            是否存在
 *
 * 这就是"框架"的价值：把重复的增删改查代码全部消灭掉。
 *
 * 尖括号里的两个参数意思是：
 *      JpaRepository<要操作的实体类, 主键的类型>
 * 所以是 <LoadRecord, Long>（LoadRecord 的 id 是 Long）
 */
public interface LoadRecordRepository extends JpaRepository<LoadRecord, Long> {

    // ============================================================
    //  一、方法名就是 SQL —— "派生查询"（Derived Query）
    // ============================================================
    //  你不用写 SQL，只要按约定给方法起名，Spring 自己解析成 SQL。
    //
    //     findBy + 字段名 + 条件
    //
    //  findByRegionName(String regionName)
    //      -> SELECT * FROM load_record WHERE region_name = ?
    //
    //  findByLoadKwGreaterThan(BigDecimal v)
    //      -> SELECT * FROM load_record WHERE load_kw > ?
    //
    //  常用后缀：GreaterThan / LessThan / Between / Like / OrderBy...Desc / And / Or
    //  字段名要用"Java 的驼峰写法"（regionName），转 SQL 时框架自动变 region_name。
    // ============================================================

    /** 按地区名查，按时间正序返回 */
    List<LoadRecord> findByRegionNameOrderByTsAsc(String regionName);

    /** 按地区编码查 */
    List<LoadRecord> findByRegionCodeOrderByTsAsc(String regionCode);

    /** 查负荷大于某个值的记录，按负荷从高到低（就是你在第 1 步练过的那条 SQL） */
    List<LoadRecord> findByLoadKwGreaterThanOrderByLoadKwDesc(BigDecimal loadKw);

    /** 查所有异常点 */
    List<LoadRecord> findByIsAnomaly(Integer isAnomaly);

    // ============================================================
    //  二、方法名不好表达时，直接写 SQL —— @Query
    // ============================================================
    //  注意：这里的 :minLoad 是"占位符"，具体值由 @Param("minLoad") 传进来。
    //  用占位符（而不是字符串拼接）能防 SQL 注入 —— 面试高频考点。
    //
    //  为什么这段用 @Query 而不用方法名？
    //  因为要一次筛"负荷在某个区间 且 属于某个地区"，用方法名会变成
    //  findByLoadKwBetweenAndRegionNameOrderByTsAsc 这种看不懂的长名字。
    //  —— 记住这个判断标准：名字念不出口了，就换 @Query。
    // ============================================================

    @Query("SELECT r FROM LoadRecord r " +
           "WHERE r.loadKw BETWEEN :minLoad AND :maxLoad " +
           "AND r.regionName = :regionName " +
           "ORDER BY r.ts ASC")
    List<LoadRecord> findByLoadRange(@Param("regionName") String regionName,
                                     @Param("minLoad") BigDecimal minLoad,
                                     @Param("maxLoad") BigDecimal maxLoad);
}
