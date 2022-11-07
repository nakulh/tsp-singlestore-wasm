extern crate time;
extern crate travelling_salesman;
use ndarray::{Array2};
use wkt::{TryFromWkt, ToWkt};
use geo_types::{Point, coord, LineString};

wit_bindgen_rust::export!("tsp.wit");
use crate::tsp::Destinations;
use crate::tsp::ToUpdatePoints;
struct Tsp;

impl tsp::Tsp for Tsp {
    fn tsp_of(geo: Vec<Destinations>, n_clusters: i32) -> Vec<String> {
        let n_clusters: usize = n_clusters as usize;
        // lon, lat, lon, lat
        /*geo.push(Destinations {
            destination: ("POINT(1 1)").to_string(),
        });*/
        let mut coordinates_base = Array2::<f64>::zeros((geo.len(), 2));
        //let data = vec![-74.006f64, 40.7128f64, -0.1278f64, 51.5074f64, -73.10621, 64.43155];
        let mut point_index = 0;
        for input_point in geo{
            let point: Point<f64> = Point::try_from_wkt_str(&input_point.destination).unwrap();
            coordinates_base[[point_index, 0]] = point.x();
            coordinates_base[[point_index, 1]] = point.y();
            point_index += 1;
        }
        //let coordinates_base = Array2::from_shape_vec((data.len() / 2, 2), data).unwrap();
        let coordinates = coordinates_base.view();
        let (means, _clusters) = rkm::kmeans_lloyd(&coordinates, n_clusters);
        println!("means: {:?} \n clusters: {:?}", means, _clusters);

        let mut city_clusters = Vec::new();
        let mut paths: Vec<Vec<(f64, f64)>> = Vec::new();
        for x in 0..n_clusters {
            city_clusters.push(Vec::new());
            paths.push(Vec::new());
        }
        let mut i = 0;
        for coordinate in coordinates.outer_iter() {
            city_clusters[_clusters[i]].push((coordinate[0], coordinate[1]));
            i += 1;
        }
        println!("clusters: {:?}", city_clusters);
        let mut paths = Vec::new();
        for cities in city_clusters.iter() {
            let tour = travelling_salesman::simulated_annealing::solve(
                &cities,
                time::Duration::milliseconds(100),
              );
              println!("Tour distance: {}, route: {:?}", tour.distance, tour.route);
              println!("Distance matrix: {:?}", travelling_salesman::get_distance_matrix(cities));
              let mut path = Vec::new();
              for city_index in tour.route.iter() {
                path.push(coord!{
                    x: cities[*city_index].0,
                    y: cities[*city_index].1
                })
              }
              //let line_string = LineString::new(path);
              paths.push(LineString::new(path).wkt_string());
        }
        paths
    }

    fn tsp_update(toUpdateVec: Vec<ToUpdatePoints>, existingPaths: Vec<String>) -> Vec<String> {
        let mut listOfPaths = Vec::new();
        let mut i = 0;
        for path in existingPaths {
            listOfPaths.push(Vec::new());
            let curr_line: Vec<geo_types::Point<f64>> = LineString::try_from_wkt_str(&path).unwrap().clone().into_points();
            for currPoint in curr_line {
                listOfPaths[i].push((currPoint.x(), currPoint.y()));
            }
            i += 1;
        }
        for toUpdatePoint in toUpdateVec {
            let currPoint: Point<f64> = Point::try_from_wkt_str(&toUpdatePoint.point).unwrap();
            listOfPaths[toUpdatePoint.existing_index as usize].push((currPoint.x(), currPoint.y()));
        }
        let mut paths = Vec::new();
        i = 0;
        for cities in listOfPaths {
            let tour = travelling_salesman::simulated_annealing::solve(
                &cities,
                time::Duration::milliseconds(100),
              );
              println!("Tour distance: {}, route: {:?}", tour.distance, tour.route);
              println!("Distance matrix: {:?}", travelling_salesman::get_distance_matrix(&cities));
              let mut path = Vec::new();
              for city_index in tour.route.iter() {
                path.push(coord!{
                    x: cities[*city_index].0,
                    y: cities[*city_index].1
                })
              }
              //let line_string = LineString::new(path);
              paths.push(LineString::new(path).wkt_string());
            i += 1;
        }
        paths
    }
}

