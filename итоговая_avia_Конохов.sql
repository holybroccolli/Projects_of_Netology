SET search_path = bookings    --установка схемы bookings - по умолчанию

-- 1. В каких городах больше одного аэропорта?
/* Данные из таблицы airports группирую по полю city, при выводе использую агрегирующую функцию count по полю city.
 * Использую оператор having с условием после группировки. В итоговый набор попадают все города, где агрегация дала значение больше 1.
*/
select city , count(city)
from airports a 							
group by city							
having count(city) >1


--для облачного подключения, тест
select city , count(city)
from airports_data ad  							
group by city							
having count(city) >1

-- 2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета? -Подзапрос

/*С помощью подзапроса из упорядоченной по убыванию дальности полета (range) таблицы с моделелями
 * воздушных суден выбираю первую запись (Boeing 777-333 / 11 100).
 * Далее нахожу пересечение (inner join) таблицы рейсов (flights) с результатом подзапроса по полю aircraft_code.
 * По коду аэропорта (airport_code / departure_airport) присоединяю таблицу с названиями аэропортов (airports).
 * Присоединение можно было делать и по arrival_airport, так как поля идентичны, в таблице каждый рейс имеет обратный.
 * Так как коды/названия аэропортов дублируются, при выводе использую оператор DISTINCT для обора уникальных значений
 * Выводимому полю присваиваю название "Аэропорты" */
 

select distinct ap.airport_name as "Аэропорты" 
from 		(select * from aircrafts ac 
			order by "range" desc
			limit 1
			) t
inner join flights f using(aircraft_code)
join airports ap on ap.airport_code = f.departure_airport 
order by 1



-- 3. Вывести 10 рейсов с максимальным временем задержки вылета -Оператор LIMIT
/*Из таблицы рейсов flights вывожу Идентификатор рейса flight_id и вычисляемое поле - разницу 
 * между фактическим и плановым временем вылета (actual_departure - scheduled_departure).
 * Условием is not null на вычисляемое поле исключаю рейсы, которые не состоялись или планируемые.
 * Сортирую по убыванию разницы (order by) и устанавливаю ограничение на выводимое количество записей (limit 10)
 */

select flight_id , (actual_departure - scheduled_departure) as max_delay 
from flights f 
where (actual_departure-scheduled_departure) is not null
order by 2 desc
limit 10



-- 4. Были ли брони, по которым не были получены посадочные талоны -Верный тип JOIN
/*Таблицу с бронированиями (bookings) джойню с таблицей билетов (tickets) по номеру бронирования для
 * того, чтобы далее присоединить слева таблицу с посадочными талонами (boarding_passes)
 * В случае наличия броней без посадочных талонов номер посадочного талона будет null.
 * Задавая условие bp.boarding_no is null оставляю в выборке только брони без ПТ. В select агрегирую оставшиеся записи с помощью count.
 * Если счетчик будет нулевым, то количество броней и количество посадочных талонов совпадают/
 */


select count(*) "Количество броней без посадочных"
from bookings b 
join tickets t using(book_ref)
left join boarding_passes bp using(ticket_no)
where bp.boarding_no is null

			

	



-- 5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
--Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. 
--Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах
--в течении дня. -Оконная функция, подзапросы и/или СТЕ

/*
 *Использую СТЕ, в котором из таблицы flights, соединенной (join) с таблицей boarding_passes,
 *выбираются рейс (flight_id), код самолета (aircraft_code), аэропорт отправления (departure_airport), 
 *фактические дата и время вылета (actual_departure), а также  и количество (агрегация count) выданных 
 *посадочных талонов, т.е. фактическое заполнение борта.
 *С помощью вэр выбираются рейсы со статусом Arrived или Departed, так как в остальных случаях 
 *фактическая информация о загрузке на момент вылета может быть неверной. Группировка по flight_id.
 *
 *В основном запросе использую подзапрос в операторе from для подсчета вместимости судна в разрезе модели самолета.
 *Джойню СТЕ к результату подзапроса по коду самолета (aircraft_code).
 *В select указываю flight_id, departure_airport, actual_departure в типе данных date, фактическое заполнение борта.
 *С помощью оконной функции определяю суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день.
 *Далее: вместимость, свободные места на каждом рейсе и процентное отношение к общему количеству мест в самолете.
 */
select * from flights

with cte as (
		select f.flight_id , 
		f.aircraft_code ,
		f.departure_airport ,
		f.actual_departure ,
		count(boarding_no) as actual_fill 
		from flights f
		join boarding_passes bp using(flight_id) 
		where status = 'Arrived' or status = 'Departed'
		group by flight_id 
				)
select 	flight_id,
		cte.departure_airport, cte.actual_departure::date,
		actual_fill, 
		sum(actual_fill) over (partition by cte.departure_airport, cte.actual_departure::date order by cte.actual_departure) as cumulative,
		capacity, 
		(capacity-actual_fill) as "vacant, pc", 
		round((capacity-actual_fill)*100.0/capacity, 2) /*|| '%'*/ as "vacant,%"		
from (	select s.aircraft_code , count (s.seat_no) as capacity
		from seats s 
		group by s.aircraft_code 
		) uq
join cte using (aircraft_code)


-- 6. Найдите процентное соотношение перелетов по типам самолетов от общего количества. -Подзапрос или окно. Оператор ROUND
/*В основном запросе таблицу aircrafts джойню с таблицей рейсов flights по полю кода самолета. Результат группирую по модели и коду самолета.
 * В операторе select для вывода результата с помощью подзапроса агрегирую количество рейсов с условием завершенности: status = 'Arrived'.
 * Для подсчета процентного соотношения применяю оператор round - округление до двух десятичных знаков.  
 */


select	a.model,
		count(f.flight_id ) as "by_type", 
			(select count(flight_id)
			from flights f
			where status = 'Arrived') as total,
		round(count(f.flight_id )*100.0/(select count(flight_id)
										from flights f
										where status = 'Arrived'),2) as "by_type/total"
from aircrafts a
join flights f using(aircraft_code)
group by a.model , f.aircraft_code 
			
			
-- 7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета? -CTE




-- 8. Между какими городами нет прямых рейсов? -- Декартово произведение в предложении FROM
--Самостоятельно созданные представления (если облачное подключение, то без представления)/  - Оператор EXCEPT

/* Над таблицей рейсов (flights) создаю представление с городами, между которыми существуют прямые рейсы:
 * - Так как в flights нет названий городов, в которых находятся аэропорты, приджойнил их. 
 * - Оператором distinct исключаю дубликаты.
 * Далее, кросс-джойн таблицы airports, получаю всевозможные сочетания городов.
 * Исключаю из выборки записи где города совпадают.
 * На вывод в select только два поля с городами, так как оператор except работает с одинаковыми таблицами (по полям).
 * Из полученной выборки исключаю результат созданного ранее представления routes_t, т.е. города, между которыми существуют рейсы. 
 */ 

create view routes_t as
select distinct	
		a.city as departure,
		a2.city as arrival
from flights f
join airports a on a.airport_code = f.departure_airport 
join airports a2 on a2.airport_code = f.arrival_airport  

--drop view routes_t 

select 	a1.city as point_A,
		a2.city as point_B
from airports a1
cross join airports a2
where a1.city <> a2.city 
except
select *
from routes_t

--Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью перелетов 
--в самолетах, обслуживающих эти рейсы *.  -

/** - В облачной базе координаты находятся в столбце airports_data.coordinates - работаете, как с массивом. В локальной базе координаты находятся в столбцах airports.longitude и airports.latitude.
Кратчайшее расстояние между двумя точками A и B на земной поверхности (если принять ее за сферу) определяется зависимостью:
d = arccos {sin(latitude_a)·sin(latitude_b) + cos(latitude_a)·cos(latitude_b)·cos(longitude_a - longitude_b)}, где latitude_a и latitude_b — широты, longitude_a, longitude_b — долготы данных пунктов, d — расстояние между пунктами измеряется в радианах длиной дуги большого круга земного шара.
Расстояние между пунктами, измеряемое в километрах, определяется по формуле:
L = d·R, где R = 6371 км — средний радиус земного шара.*/
--- Опера
/*
 * К таблице рейсов джойню таблицу с аэропортами для связи названий и кодов аэропортов прилета и вылета.
 * Так как данное задание выполняю на другом компьютере и нет доступа к локальной БД, то координаты для расчета расстояния между аэропортами вытягиваю из массивов таблицы airports.
 * В оператор case как условие ввожу разность между дальностью полета модели самолета на рейсе (range) и рассчитанным растоянием между аэропортами.
 * В зависимости от результата (больше или меньше нуля) вывожу отметку о проверке.
 * 
 */

select distinct 
	a1.airport_name as departure,
	a2.airport_name as arrival,
	a.range as max_distance,
	round((acos(sind(a1.coordinates[0]) * sind(a2.coordinates[0]) + cosd(a1.coordinates[0]) * cosd(a2.coordinates[0]) * cosd(a1.coordinates[1]-a2.coordinates[1])) * 6371)::decimal, 2) as distance,
	case when 
		(a.range - round((acos(sind(a1.coordinates[0]) * sind(a2.coordinates[0]) + cosd(a1.coordinates[0]) * cosd(a2.coordinates[0]) * cosd(a1.coordinates[1]-a2.coordinates[1])) * 6371)::decimal, 2))<0
		then 'Nope'
		else 'Yep'
		end  "Check"
from flights f
join airports a1 on f.departure_airport = a1.airport_code
join airports a2 on f.arrival_airport = a2.airport_code
join aircrafts a on a.aircraft_code = f.aircraft_code 



