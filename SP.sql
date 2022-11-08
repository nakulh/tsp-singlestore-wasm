
CREATE ROWSTORE TABLE flightInstance (id BIGINT PRIMARY KEY AUTO_INCREMENT, hubLocation GEOGRAPHYPOINT NOT NULL, droneCount INT NOT NULL)
CREATE ROWSTORE TABLE flightPath(id BIGINT PRIMARY KEY AUTO_INCREMENT, flightInstanceId BIGINT NOT NULL, path GEOGRAPHY NOT NULL)

DELIMITER $$
CREATE OR REPLACE PROCEDURE `getWayPoints`(currFlightInstanceId BIGINT) AS
  DECLARE
    getDroneCount QUERY(a INT) = SELECT droneCount FROM flightInstance WHERE id = currFlightInstanceId;
    currDroneCount INT;
    insertRes INT;
    p ARRAY(RECORD(destination text COLLATE utf8mb4_general_ci NOT NULL));
	flightPathArr ARRAY(RECORD(id BIGINT, flightInstanceId BIGINT NOT NULL, path GEOGRAPHY NOT NULL));
    pathArr ARRAY(TEXT COLLATE utf8mb4_general_ci NOT NULL);
    qry QUERY (destination text COLLATE utf8mb4_general_ci NOT NULL) = SELECT location :> text FROM flightPoint WHERE assignedToDrone = false and visited = false and flightInstanceId = currFlightInstanceId;
  BEGIN
    currDroneCount = SCALAR(getDroneCount);
    flightPathArr = CREATE_ARRAY(currDroneCount);
    p = COLLECT(qry);
    pathArr = tsp_of(p, currDroneCount);
    FOR i IN 0..(currDroneCount - 1) LOOP
		flightPathArr[i] = ROW(null, currFlightInstanceIdflightInstanceId, pathArr[i] :> GEOGRAPHY);
	END LOOP;
	insertRes = INSERT_ALL("flightPath", flightPathArr);
  END;$$
DELIMITER ;

DELIMITER $$
CREATE FUNCTION tsp_update AS WASM 
FROM S3 'tsp-singlestore/tsp.wasm'
CREDENTIALS '{
        "aws_access_key_id": "AKIASFVBL2RCVZNYUU6T",
        "aws_secret_access_key": "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"
    }'
    CONFIG '{"region": "ap-south-1"}'
WITH WIT FROM S3 'tsp-singlestore/tsp.wit'
CREDENTIALS '{
        "aws_access_key_id": "AKIASFVBL2RCVZNYUU6T",
        "aws_secret_access_key": "H3qF/kI+IybuR8OQTtjwOndY5RYOpXPFT2Ehubaa"
    }'
    CONFIG '{"region": "ap-south-1"}';
DELIMITER ;


DELIMITER $$
CREATE OR REPLACE PROCEDURE createFlightInstance(pointsArr ARRAY(GEOGRAPHYPOINT), hubPoint GEOGRAPHYPOINT, droneCountNum INT) RETURNS QUERY(id BIGINT, flightInstanceId BIGINT, path GEOGRAPHY) AS
DECLARE
    flightPointArr ARRAY(RECORD(id BIGINT, location GEOGRAPHYPOINT, flightInstanceId BIGINT, visited BOOL, assignedToDrone BOOL, flightPathId BIGINT)) = CREATE_ARRAY(LENGTH(pointsArr));
    currFlightInstanceId BIGINT;
    getCurrFlightInstanceId QUERY(a BIGINT) = SELECT last_insert_id();
    insertRes INT;
    #flightPathArr ARRAY(RECORD(flightInstanceId BIGINT, path GEOGRAPHY)) = CREATE_ARRAY(droneCountNum);
    #flightPathQuery QUERY(flightInstanceId BIGINT, path GEOGRAPHY) = TO_QUERY(CONCAT('SELECT flightInstanceId, path FROM flightPath where flightInstanceId = ', currFlightInstanceId));
BEGIN
	INSERT INTO flightInstance (hubLocation, droneCount) VALUES (hubPoint, droneCountNum);
    currFlightInstanceId = SCALAR(getCurrFlightInstanceId);
    FOR i IN 0..(LENGTH(pointsArr) - 1) LOOP
        flightPointArr[i] = ROW(null, pointsArr[i], currFlightInstanceId, false, false, null);
    END LOOP;
    insertRes = INSERT_ALL("flightPoint", flightPointArr);
    CALL getWayPoints(currFlightInstanceId);
    #flightPathArr = COLLECT(CONCAT('SELECT flightInstanceId, path FROM flightPath where flightInstanceId = ' , currFlightInstanceId), QUERY(flightInstanceId BIGINT, path GEOGRAPHY));
    #RETURN flightPathArr;
    RETURN TO_QUERY(CONCAT('SELECT * FROM flightPath where flightInstanceId = ', currFlightInstanceId));
end $$
DELIMITER ;

DELIMITER $$
CREATE OR REPLACE PROCEDURE killDrone(droneId BIGINT, pointsArr ARRAY(GEOGRAPHYPOINT)) RETURNS QUERY(id BIGINT, flightInstanceId BIGINT, path GEOGRAPHY) AS
DECLARE
    currFlightInstanceId BIGINT;
    getCurrFlightInstanceId QUERY(a BIGINT) = SELECT flightInstanceId from flightPath where id = droneId;
    insertRes INT;
    flightPathArr ARRAY(RECORD(id BIGINT, flightInstanceId BIGINT, path GEOGRAPHY));
    flightPathQry QUERY (id BIGINT, flightInstanceId BIGINT, path GEOGRAPHY);
    flightPathAdditionsArr ARRAY(RECORD(point TEXT COLLATE utf8mb4_general_ci NOT NULL, existing_index INT NOT NULL)) = CREATE_ARRAY(LENGTH(pointsArr));
    currClosestIndex INT = 0;
    currClosestDistance INT;
    newPathArr ARRAY(TEXT COLLATE utf8mb4_general_ci NOT NULL);
    flightPathInputArr ARRAY(TEXT COLLATE utf8mb4_general_ci NOT NULL);
    currGeo GEOGRAPHY;
    currId BIGINT;
BEGIN #14
    currFlightInstanceId = SCALAR(getCurrFlightInstanceId);
    flightPathQry = TO_QUERY(CONCAT('SELECT * FROM flightPath where flightInstanceId = ', currFlightInstanceId, " and id != ", droneId));
    flightPathArr = COLLECT(flightPathQry);
    FOR i IN 0..(LENGTH(pointsArr) - 1) LOOP
		currClosestIndex = 0;
        currClosestDistance = ROUND(GEOGRAPHY_DISTANCE(flightPathArr[0].path, pointsArr[i]));
		FOR j in 0..(LENGTH(flightPathArr) - 1) LOOP
			IF (ROUND(GEOGRAPHY_DISTANCE(flightPathArr[j].path, pointsArr[i])) < currClosestDistance) THEN
				currClosestIndex = j;
                currClosestDistance = ROUND(GEOGRAPHY_DISTANCE(flightPathArr[j].path, pointsArr[i]));
			END IF;
        END LOOP;
        flightPathAdditionsArr[i] = ROW(pointsArr[i] :> TEXT, currClosestIndex);
    END LOOP;
    flightPathInputArr = CREATE_ARRAY(LENGTH(flightPathArr));
    FOR k IN 0..(LENGTH(flightPathArr) - 1) LOOP #30
		flightPathInputArr[k] = flightPathArr[k].path :> TEXT;
    END LOOP;
    newPathArr = tsp_update(flightPathAdditionsArr, flightPathInputArr);
    FOR l in 0..(LENGTH(newPathArr) - 1) LOOP
        currGeo = newPathArr[l] :> GEOGRAPHY;
        currId = flightPathArr[l].id;
		UPDATE flightPath SET path = currGeo WHERE id = currId;
    END LOOP;
    DELETE FROM flightPath WHERE id = droneId;
    RETURN TO_QUERY(CONCAT('SELECT * FROM flightPath where flightInstanceId = ', currFlightInstanceId));
end $$
DELIMITER ;
