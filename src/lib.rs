extern crate time;
extern crate travelling_salesman;
use ndarray::{Array2};
use wkt::{TryFromWkt, ToWkt};
use geo_types::{Point, coord, LineString};

wit_bindgen_rust::export!("tsp.wit");
use crate::tsp::{Destinations, ToUpdatePoints};

struct Tsp;

impl tsp::Tsp for Tsp {
    fn tsp_of(geo: Vec<Destinations>, n_clusters: i32) -> Vec<String> {
        let n_clusters: usize = n_clusters as usize;
        let coordinates_base = geo.iter()
            .map(|d| Point::try_from_wkt_str(&d.destination).unwrap())
            .map(|p| [p.x(), p.y()])
            .collect::<Vec<_>>();
        let coordinates = Array2::from_shape_vec((coordinates_base.len(), 2), coordinates_base).unwrap();

        let (means, _clusters) = rkm::kmeans_lloyd(&coordinates.view(), n_clusters);
        println!("means: {:?} \n clusters: {:?}", means, _clusters);

        let city_clusters = _clusters.iter()
            .enumerate()
            .fold(vec![Vec::new(); n_clusters], |mut acc, (i, cluster_idx)| {
                acc[*cluster_idx].push(coordinates[[i, 0]], coordinates[[i, 1]]);
                acc
            });

        let paths = city_clusters.iter()
            .map(|cities| {
                let tour = travelling_salesman::simulated_annealing::solve(
                    cities,
                    time::Duration::milliseconds(100),
                );
                println!("Tour distance: {}, route: {:?}", tour.distance, tour.route);
                println!("Distance matrix: {:?}", travelling_salesman::get_distance_matrix(cities));

                let path = tour.route.iter()
                    .map(|city_idx| {
                        coord!{
                            x: cities[*city_idx].0,
                            y: cities[*city_idx].1
                        }
                    })
                    .collect::<Vec<_>>();
                LineString::new(path).wkt_string()
            })
            .collect::<Vec<_>>();
        paths
    }

    fn tsp_update(to_update_vec: Vec<ToUpdatePoints>, existing_paths: Vec<String>) -> Vec<String> {
        let mut list_of_paths = existing_paths.iter()
            .map(|path| {
                let curr_line: Vec<Point<f64>> = LineString::try_from_wkt_str(path).unwrap().into_points();
                curr_line.iter().map(|p| (p.x(), p.y())).collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();

        for to_update_point in to_update_vec {
            let curr_point: Point<f64> = Point::try_from_wkt_str(&to_update_point.point).unwrap();
            list_of_paths[to_update_point.existing_index as usize].push((curr_point.x(), curr_point.y()));
        }

        let paths = list_of_paths.iter()
            .enumerate()
            .map(|(i, cities)| {
                let tour = travelling_salesman::simulated_annealing::solve(
                    cities,
                    time::Duration::milliseconds(100),
                );
                println!("Tour distance: {}, route: {:?}", tour.distance, tour.route);
                println!("Distance matrix: {:?}", travelling_salesman::get_distance_matrix(cities));

                let path = tour.route.iter()
                    .map(|city_idx| {
                        coord!{
                            x: cities[*city_idx].0,
                            y: cities[*city_idx].1
                        }
                    })
                    .collect::<Vec<_>>();
                LineString::new(path).wkt_string()
            })
           
